module Quo
  # Immutable UPDATE query builder
  # Each method returns a new UpdateQuery instance, leaving the original unchanged
  class UpdateQuery
    getter table : Symbol
    getter set_values : Hash(Symbol, DB::Any)
    getter where_clauses : Array(Expression)
    getter returning_columns : Array(ColumnRef)

    @adapter : Adapters::Adapter

    def initialize(
      @table : Symbol,
      @adapter : Adapters::Adapter,
      @set_values : Hash(Symbol, DB::Any) = {} of Symbol => DB::Any,
      @where_clauses : Array(Expression) = [] of Expression,
      @returning_columns : Array(ColumnRef) = [] of ColumnRef
    )
    end

    # SET - specify column values to update
    # Example: .set(name: "New Name", status: "active")
    def set(**columns) : UpdateQuery
      new_values = @set_values.dup
      columns.each do |key, value|
        new_values[key] = value.as(DB::Any)
      end
      copy_with(set_values: new_values)
    end

    # SET from hash
    def set(columns : Hash(Symbol, DB::Any)) : UpdateQuery
      new_values = @set_values.merge(columns)
      copy_with(set_values: new_values)
    end

    # WHERE with hash - table-qualified conditions
    # Example: .where(users: {id: 1})
    def where(**conditions) : UpdateQuery
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
    def where(&block : ExpressionBuilder -> Expression) : UpdateQuery
      builder = ExpressionBuilder.new
      expr = yield builder
      copy_with(where_clauses: @where_clauses + [expr])
    end

    # RETURNING clause (PostgreSQL)
    # Example: .returning(users: [:id, :updated_at])
    def returning(**columns) : UpdateQuery
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
      @adapter.compile_update(self)
    end

    # Execute the update and return number of affected rows
    def execute : Int64
      sql, params = to_sql
      @adapter.execute_update(sql, params)
    end

    # Execute the update and return the updated rows (requires RETURNING)
    # Returns Quo::ResultSet with rich types preserved
    def execute_returning : Quo::ResultSet
      raise QueryError.new("RETURNING clause required for execute_returning") if @returning_columns.empty?
      sql, params = to_sql
      @adapter.execute(sql, params)
    end

    # Debug output
    def inspect(io : IO) : Nil
      io << "#<Quo::UpdateQuery"
      io << " table=:" << @table
      io << " set=" << @set_values.size << " columns"
      io << " where=" << @where_clauses.size << " clauses" unless @where_clauses.empty?
      io << " returning=" << @returning_columns.size << " columns" unless @returning_columns.empty?
      io << ">"
    end

    private def copy_with(
      set_values : Hash(Symbol, DB::Any) = @set_values,
      where_clauses : Array(Expression) = @where_clauses,
      returning_columns : Array(ColumnRef) = @returning_columns
    ) : UpdateQuery
      UpdateQuery.new(
        table: @table,
        adapter: @adapter,
        set_values: set_values,
        where_clauses: where_clauses,
        returning_columns: returning_columns
      )
    end
  end
end
