require "./expression"
require "./expression_builder"
require "./column_ref"
require "./aggregation"
require "./aggregate_expression_builder"
require "./set_operation"
require "./cte"

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
    getter select_columns : Array(SelectColumn)
    getter where_clauses : Array(Expression)
    getter joins : Array(Join)
    getter order_clauses : Array(OrderClause)
    getter limit_value : Int32?
    getter offset_value : Int32?
    getter? distinct_enabled : Bool
    getter aggregates : Array(Aggregate)
    getter group_columns : Array(GroupColumn)
    getter having_clauses : Array(HavingExpression)
    getter set_operations : Array(SetOperation)
    getter cte_clauses : Array(CTE)

    # Forward declaration for adapter - will be defined in adapters/
    @adapter : Adapters::Adapter

    def initialize(
      @table : Symbol,
      @adapter : Adapters::Adapter,
      @select_columns : Array(SelectColumn) = [] of SelectColumn,
      @where_clauses : Array(Expression) = [] of Expression,
      @joins : Array(Join) = [] of Join,
      @order_clauses : Array(OrderClause) = [] of OrderClause,
      @limit_value : Int32? = nil,
      @offset_value : Int32? = nil,
      @distinct_enabled : Bool = false,
      @aggregates : Array(Aggregate) = [] of Aggregate,
      @group_columns : Array(GroupColumn) = [] of GroupColumn,
      @having_clauses : Array(HavingExpression) = [] of HavingExpression,
      @set_operations : Array(SetOperation) = [] of SetOperation,
      @cte_clauses : Array(CTE) = [] of CTE
    )
    end

    # SELECT - specify columns with table qualification
    # Example: .select(contracts: [:id, :reference], users: [:name])
    def select(**columns) : Query
      new_columns = [] of SelectColumn
      columns.each do |table, cols|
        cols.each do |col|
          new_columns << ColumnRef.new(table, col)
        end
      end
      copy_with(select_columns: @select_columns + new_columns)
    end

    # SELECT with column references (supports aliasing)
    # Example: .select(t(:profiles)[:id], t(:organizations)[:name].aliased(:org_name))
    def select(*columns : SelectColumn) : Query
      copy_with(select_columns: @select_columns + columns.to_a)
    end

    # WHERE with hash - table-qualified conditions
    # Example: .where(contracts: {status: "active", user_id: id})
    def where(**conditions) : Query
      new_clauses = [] of Expression
      conditions.each do |table, hash|
        hash.each do |column, value|
          col_ref = ColumnRef.new(table, column)
          new_clauses << Eq.new(col_ref, value.as(Quo::Value))
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

    # GROUP BY - specify grouping columns
    # Example: .group(orders: [:status, :user_id])
    def group(**columns) : Query
      new_groups = [] of GroupColumn
      columns.each do |table, cols|
        cols.each do |col|
          new_groups << GroupColumn.new(table, col)
        end
      end
      copy_with(group_columns: @group_columns + new_groups)
    end

    # HAVING with expression block
    # Example: .having { count > 5 }
    def having(&block : AggregateExpressionBuilder -> HavingExpression) : Query
      builder = AggregateExpressionBuilder.new
      expr = yield builder
      copy_with(having_clauses: @having_clauses + [expr])
    end

    # SELECT COUNT(*) - add count aggregate
    # Example: .select_count(as: :total_count)
    def select_count(*, as alias_name : Symbol? = nil) : Query
      agg = Aggregate.count(as: alias_name)
      copy_with(aggregates: @aggregates + [agg])
    end

    # SELECT COUNT(column) - count non-null values
    # Example: .select_count(:users, :email, as: :email_count, distinct: true)
    def select_count(table : Symbol, column : Symbol, *, as alias_name : Symbol? = nil, distinct : Bool = false) : Query
      agg = Aggregate.count(table, column, as: alias_name, distinct: distinct)
      copy_with(aggregates: @aggregates + [agg])
    end

    # SELECT SUM(column)
    # Example: .select_sum(:orders, :amount, as: :total_amount)
    def select_sum(table : Symbol, column : Symbol, *, as alias_name : Symbol? = nil) : Query
      agg = Aggregate.sum(table, column, as: alias_name)
      copy_with(aggregates: @aggregates + [agg])
    end

    # SELECT AVG(column)
    # Example: .select_avg(:products, :price, as: :average_price)
    def select_avg(table : Symbol, column : Symbol, *, as alias_name : Symbol? = nil) : Query
      agg = Aggregate.avg(table, column, as: alias_name)
      copy_with(aggregates: @aggregates + [agg])
    end

    # SELECT MIN(column)
    # Example: .select_min(:orders, :created_at, as: :first_order)
    def select_min(table : Symbol, column : Symbol, *, as alias_name : Symbol? = nil) : Query
      agg = Aggregate.min(table, column, as: alias_name)
      copy_with(aggregates: @aggregates + [agg])
    end

    # SELECT MAX(column)
    # Example: .select_max(:orders, :amount, as: :largest_order)
    def select_max(table : Symbol, column : Symbol, *, as alias_name : Symbol? = nil) : Query
      agg = Aggregate.max(table, column, as: alias_name)
      copy_with(aggregates: @aggregates + [agg])
    end

    # UNION - combine results, removing duplicates
    # Example: active_users.union(admin_users)
    def union(other : Query) : Query
      op = SetOperation.new(SetOperationType::Union, other)
      copy_with(set_operations: @set_operations + [op])
    end

    # UNION ALL - combine results, keeping duplicates
    # Example: active_users.union_all(admin_users)
    def union_all(other : Query) : Query
      op = SetOperation.new(SetOperationType::UnionAll, other)
      copy_with(set_operations: @set_operations + [op])
    end

    # INTERSECT - return only common rows
    # Example: active_users.intersect(premium_users)
    def intersect(other : Query) : Query
      op = SetOperation.new(SetOperationType::Intersect, other)
      copy_with(set_operations: @set_operations + [op])
    end

    # INTERSECT ALL - return common rows with duplicates
    # Example: active_users.intersect_all(premium_users)
    def intersect_all(other : Query) : Query
      op = SetOperation.new(SetOperationType::IntersectAll, other)
      copy_with(set_operations: @set_operations + [op])
    end

    # EXCEPT - return rows in first query not in second
    # Example: all_users.except(deleted_users)
    def except(other : Query) : Query
      op = SetOperation.new(SetOperationType::Except, other)
      copy_with(set_operations: @set_operations + [op])
    end

    # EXCEPT ALL - return rows not in second, keeping duplicates
    # Example: all_users.except_all(deleted_users)
    def except_all(other : Query) : Query
      op = SetOperation.new(SetOperationType::ExceptAll, other)
      copy_with(set_operations: @set_operations + [op])
    end

    # WITH - add a Common Table Expression (CTE)
    # Example: .with_cte(:active_users, query)
    def with_cte(name : Symbol, cte_query : Query, *, recursive : Bool = false) : Query
      cte = CTE.new(name, cte_query, recursive)
      copy_with(cte_clauses: @cte_clauses + [cte])
    end

    # WITH RECURSIVE - add a recursive CTE (simple form)
    # Example: .with_recursive_cte(:tree, recursive_query)
    def with_recursive_cte(name : Symbol, cte_query : Query) : Query
      with_cte(name, cte_query, recursive: true)
    end

    # WITH RECURSIVE - add a recursive CTE with base case and recursive case
    # This creates: WITH RECURSIVE name AS (base_query UNION ALL recursive_query)
    # Example:
    #   base = Query.new(:categories, adapter).where(categories: {parent_id: nil})
    #   recursive = Query.new(:categories, adapter).join(:tree, on: {...})
    #   query.with_recursive_cte(:tree, base: base, recursive: recursive)
    def with_recursive_cte(name : Symbol, *, base base_query : Query, recursive recursive_query : Query) : Query
      new_cte = CTE.new(name, base: base_query, recursive: recursive_query)
      copy_with(cte_clauses: @cte_clauses + [new_cte])
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
        distinct_enabled: @distinct_enabled || other.distinct_enabled?,
        aggregates: @aggregates + other.aggregates,
        group_columns: @group_columns + other.group_columns,
        having_clauses: @having_clauses + other.having_clauses,
        set_operations: @set_operations + other.set_operations,
        cte_clauses: @cte_clauses + other.cte_clauses
      )
    end

    # Generate SQL and parameters tuple
    def to_sql : {String, Array(Quo::Value)}
      @adapter.compile(self)
    end

    # Generate COUNT SQL
    def count_sql : {String, Array(Quo::Value)}
      @adapter.compile_count(self)
    end

    # Execute query and return array of hashes
    # Execute query and return results
    # Returns Quo::ResultSet with rich types preserved (UUID, PG::Numeric, etc.)
    def to_a : Quo::ResultSet
      # Measure compile time
      compile_start = Time.utc
      sql, params = to_sql
      compile_time = Time.utc - compile_start

      # Execute with timing
      Logging.instrument_with_timing(sql, params, :select, compile_time) do
        @adapter.execute(sql, params)
      end
    end

    # Execute query and map to type T
    def to_a(as type : T.class) : Array(T) forall T
      # Measure compile time
      compile_start = Time.utc
      sql, params = to_sql
      compile_time = Time.utc - compile_start

      # Execute with timing
      Logging.instrument_with_timing(sql, params, :select, compile_time) do
        @adapter.execute(sql, params, as: type)
      end
    end

    # Get first result or nil
    # Returns Quo::Row with rich types preserved
    def first : Quo::Row?
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
    # Returns Quo::Row with rich types preserved
    def first! : Quo::Row
      first || raise RecordNotFound.new(@table)
    end

    # Get first result mapped to type T or raise RecordNotFound
    def first!(as type : T.class) : T forall T
      first(as: type) || raise RecordNotFound.new(@table)
    end

    # Count matching rows
    def count : Int64
      # Measure compile time
      compile_start = Time.utc
      sql, params = count_sql
      compile_time = Time.utc - compile_start

      # Execute with timing
      Logging.instrument_with_timing(sql, params, :select, compile_time) do
        @adapter.execute_scalar(sql, params, as: Int64)
      end
    end

    # Check if any matching rows exist
    def exists? : Bool
      count > 0
    end

    # Debug output
    def inspect(io : IO) : Nil
      io << "#<Quo::Query"
      io << " cte=" << @cte_clauses.size unless @cte_clauses.empty?
      io << " table=:" << @table
      io << " select=" << @select_columns unless @select_columns.empty?
      io << " aggregates=" << @aggregates.size unless @aggregates.empty?
      io << " where=" << @where_clauses.size << " clauses" unless @where_clauses.empty?
      io << " joins=" << @joins.size unless @joins.empty?
      io << " group=" << @group_columns.size << " columns" unless @group_columns.empty?
      io << " having=" << @having_clauses.size << " clauses" unless @having_clauses.empty?
      io << " set_ops=" << @set_operations.size unless @set_operations.empty?
      io << " order=" << @order_clauses unless @order_clauses.empty?
      io << " limit=" << @limit_value if @limit_value
      io << " offset=" << @offset_value if @offset_value
      io << " distinct" if @distinct_enabled
      io << ">"
    end

    # Create a copy of this query with modified fields
    # Used internally and by Relation for association joins
    def copy_with(
      select_columns : Array(SelectColumn) = @select_columns,
      where_clauses : Array(Expression) = @where_clauses,
      joins : Array(Join) = @joins,
      order_clauses : Array(OrderClause) = @order_clauses,
      limit_value : Int32? = @limit_value,
      offset_value : Int32? = @offset_value,
      distinct_enabled : Bool = @distinct_enabled,
      aggregates : Array(Aggregate) = @aggregates,
      group_columns : Array(GroupColumn) = @group_columns,
      having_clauses : Array(HavingExpression) = @having_clauses,
      set_operations : Array(SetOperation) = @set_operations,
      cte_clauses : Array(CTE) = @cte_clauses
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
        distinct_enabled: distinct_enabled,
        aggregates: aggregates,
        group_columns: group_columns,
        having_clauses: having_clauses,
        set_operations: set_operations,
        cte_clauses: cte_clauses
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
