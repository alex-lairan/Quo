module Quo
  # Immutable DELETE query builder
  # Each method returns a new DeleteQuery instance, leaving the original unchanged
  class DeleteQuery
    getter table : Symbol
    getter where_clauses : Array(Expression)
    getter returning_columns : Array(ColumnRef)

    @adapter : Adapters::Adapter

    def initialize(
      @table : Symbol,
      @adapter : Adapters::Adapter,
      @where_clauses : Array(Expression) = [] of Expression,
      @returning_columns : Array(ColumnRef) = [] of ColumnRef
    )
    end

    # WHERE with hash - table-qualified conditions
    # Example: .where(users: {id: 1})
    def where(**conditions) : DeleteQuery
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
    # Example: .where { users[:id] == 1 }
    def where(&block : ExpressionBuilder -> Expression) : DeleteQuery
      builder = ExpressionBuilder.new
      expr = yield builder
      copy_with(where_clauses: @where_clauses + [expr])
    end

    # RETURNING clause (PostgreSQL)
    # Example: .returning(users: [:id, :deleted_at])
    def returning(**columns) : DeleteQuery
      new_columns = [] of ColumnRef
      columns.each do |table, cols|
        cols.each do |col|
          new_columns << ColumnRef.new(table, col)
        end
      end
      copy_with(returning_columns: @returning_columns + new_columns)
    end

    # Generate SQL and parameters tuple
    def to_sql : {String, Array(DB::Any)}
      @adapter.compile_delete(self)
    end

    # Execute the delete and return number of affected rows
    def execute : Int64
      sql, params = to_sql
      @adapter.execute_delete(sql, params)
    end

    # Execute the delete and return the deleted rows (requires RETURNING)
    def execute_returning : Array(Hash(String, DB::Any))
      raise QueryError.new("RETURNING clause required for execute_returning") if @returning_columns.empty?
      sql, params = to_sql
      @adapter.execute(sql, params)
    end

    # Debug output
    def inspect(io : IO) : Nil
      io << "#<Quo::DeleteQuery"
      io << " table=:" << @table
      io << " where=" << @where_clauses.size << " clauses" unless @where_clauses.empty?
      io << " returning=" << @returning_columns.size << " columns" unless @returning_columns.empty?
      io << ">"
    end

    private def copy_with(
      where_clauses : Array(Expression) = @where_clauses,
      returning_columns : Array(ColumnRef) = @returning_columns
    ) : DeleteQuery
      DeleteQuery.new(
        table: @table,
        adapter: @adapter,
        where_clauses: where_clauses,
        returning_columns: returning_columns
      )
    end
  end
end
