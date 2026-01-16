module Quo
  # Immutable INSERT query builder
  # Each method returns a new InsertQuery instance, leaving the original unchanged
  class InsertQuery
    getter table : Symbol
    getter values_list : Array(Hash(Symbol, DB::Any))
    getter returning_columns : Array(ColumnRef)

    @adapter : Adapters::Adapter

    def initialize(
      @table : Symbol,
      @adapter : Adapters::Adapter,
      @values_list : Array(Hash(Symbol, DB::Any)) = [] of Hash(Symbol, DB::Any),
      @returning_columns : Array(ColumnRef) = [] of ColumnRef
    )
    end

    # Set values to insert (single row)
    # Example: .values(name: "Alice", email: "alice@example.com")
    def values(**columns) : InsertQuery
      row = {} of Symbol => DB::Any
      columns.each do |key, value|
        row[key] = value.as(DB::Any)
      end
      copy_with(values_list: @values_list + [row])
    end

    # Set values to insert from hash
    def values(columns : Hash(Symbol, DB::Any)) : InsertQuery
      copy_with(values_list: @values_list + [columns])
    end

    # Set values to insert from NamedTuple
    def values(columns : NamedTuple) : InsertQuery
      row = {} of Symbol => DB::Any
      columns.each do |key, value|
        row[key] = value.as(DB::Any)
      end
      copy_with(values_list: @values_list + [row])
    end

    # Insert multiple rows at once
    # Example: .values_many([{name: "Alice"}, {name: "Bob"}])
    def values_many(rows : Array(Hash(Symbol, DB::Any))) : InsertQuery
      copy_with(values_list: @values_list + rows)
    end

    def values_many(rows : Array(NamedTuple)) : InsertQuery
      converted = rows.map do |row|
        h = {} of Symbol => DB::Any
        row.each { |k, v| h[k] = v.as(DB::Any) }
        h
      end
      copy_with(values_list: @values_list + converted)
    end

    # RETURNING clause (PostgreSQL)
    # Example: .returning(users: [:id, :created_at])
    def returning(**columns) : InsertQuery
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
      @adapter.compile_insert(self)
    end

    # Execute the insert and return number of affected rows
    def execute : Int64
      sql, params = to_sql
      @adapter.execute_insert(sql, params)
    end

    # Execute the insert and return the inserted rows (requires RETURNING)
    def execute_returning : Array(Hash(String, DB::Any))
      raise QueryError.new("RETURNING clause required for execute_returning") if @returning_columns.empty?
      sql, params = to_sql
      @adapter.execute(sql, params)
    end

    # Execute and return first row (useful with RETURNING for single insert)
    def execute_returning_one : Hash(String, DB::Any)?
      results = execute_returning
      results.first?
    end

    # Debug output
    def inspect(io : IO) : Nil
      io << "#<Quo::InsertQuery"
      io << " table=:" << @table
      io << " rows=" << @values_list.size
      io << " returning=" << @returning_columns.size << " columns" unless @returning_columns.empty?
      io << ">"
    end

    private def copy_with(
      values_list : Array(Hash(Symbol, DB::Any)) = @values_list,
      returning_columns : Array(ColumnRef) = @returning_columns
    ) : InsertQuery
      InsertQuery.new(
        table: @table,
        adapter: @adapter,
        values_list: values_list,
        returning_columns: returning_columns
      )
    end
  end
end
