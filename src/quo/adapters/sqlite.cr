require "db"

module Quo
  module Adapters
    # SQLite adapter for SQL generation and execution
    class SQLite < Adapter
      @connection : DB::Database?

      def initialize(@connection : DB::Database? = nil)
      end

      # Set connection after initialization
      def connection=(conn : DB::Database)
        @connection = conn
      end

      # Compile a Query into SQL and parameters
      def compile(query : Query) : {String, Array(DB::Any)}
        params = [] of DB::Any

        sql = String.build do |str|
          # SELECT clause
          str << "SELECT "
          str << "DISTINCT " if query.distinct_enabled?
          str << compile_select(query)

          # FROM clause
          str << " FROM "
          str << quote_identifier(query.table)

          # JOIN clauses
          query.joins.each do |join|
            str << compile_join(join)
          end

          # WHERE clause
          unless query.where_clauses.empty?
            str << " WHERE "
            where_parts = query.where_clauses.map do |expr|
              sql_part, expr_params = compile_expression(expr)
              params.concat(expr_params)
              sql_part
            end
            str << where_parts.join(" AND ")
          end

          # ORDER BY clause
          unless query.order_clauses.empty?
            str << " ORDER BY "
            str << compile_order(query.order_clauses)
          end

          # LIMIT clause
          if limit = query.limit_value
            str << " LIMIT "
            str << placeholder
            params << limit.as(DB::Any)
          end

          # OFFSET clause
          if offset = query.offset_value
            str << " OFFSET "
            str << placeholder
            params << offset.as(DB::Any)
          end
        end

        {sql, params}
      end

      # Compile COUNT query
      def compile_count(query : Query) : {String, Array(DB::Any)}
        params = [] of DB::Any

        sql = String.build do |str|
          str << "SELECT COUNT(*) FROM "
          str << quote_identifier(query.table)

          # JOIN clauses
          query.joins.each do |join|
            str << compile_join(join)
          end

          # WHERE clause
          unless query.where_clauses.empty?
            str << " WHERE "
            where_parts = query.where_clauses.map do |expr|
              sql_part, expr_params = compile_expression(expr)
              params.concat(expr_params)
              sql_part
            end
            str << where_parts.join(" AND ")
          end
        end

        {sql, params}
      end

      # Quote identifier with double quotes (SQLite supports this)
      def quote_identifier(name : Symbol) : String
        "\"#{name}\""
      end

      # SQLite uses ? for all parameters (positional)
      def placeholder(index : Int32 = 0) : String
        "?"
      end

      # Execute query and return results as hash array
      def execute(sql : String, params : Array(DB::Any)) : Array(Hash(String, DB::Any))
        connection = @connection || raise AdapterError.new("No database connection")
        results = [] of Hash(String, DB::Any)

        connection.query(sql, args: params) do |rs|
          rs.each do
            row = {} of String => DB::Any
            rs.column_count.times do |i|
              col_name = rs.column_name(i)
              row[col_name] = rs.read
            end
            results << row
          end
        end

        results
      end

      # Execute query and map to type T
      def execute(sql : String, params : Array(DB::Any), as type : T.class) : Array(T) forall T
        connection = @connection || raise AdapterError.new("No database connection")
        connection.query_all(sql, args: params, as: type)
      end

      # Execute scalar query
      def execute_scalar(sql : String, params : Array(DB::Any), as type : T.class) : T forall T
        connection = @connection || raise AdapterError.new("No database connection")
        connection.query_one(sql, args: params, as: type)
      end

      private def compile_select(query : Query) : String
        if query.select_columns.empty?
          "#{quote_identifier(query.table)}.*"
        else
          query.select_columns.map do |col|
            "#{quote_identifier(col.table)}.#{quote_identifier(col.column)}"
          end.join(", ")
        end
      end

      private def compile_join(join : Join) : String
        type_str = case join.type
                   in JoinType::Inner then "INNER JOIN"
                   in JoinType::Left  then "LEFT JOIN"
                   in JoinType::Right
                     # SQLite doesn't support RIGHT JOIN natively
                     # We could emulate it but for now raise an error
                     raise AdapterError.new("SQLite does not support RIGHT JOIN. Use LEFT JOIN with reversed tables instead.")
                   in JoinType::Full
                     # SQLite doesn't support FULL JOIN natively
                     raise AdapterError.new("SQLite does not support FULL OUTER JOIN. Use UNION of LEFT JOINs instead.")
                   end

        cond = join.condition
        " #{type_str} #{quote_identifier(join.table)} ON " \
        "#{quote_identifier(cond.left_table)}.#{quote_identifier(cond.left_column)} = " \
        "#{quote_identifier(cond.right_table)}.#{quote_identifier(cond.right_column)}"
      end

      private def compile_expression(expr : Expression) : {String, Array(DB::Any)}
        case expr
        when ColumnRef
          {compile_column(expr), [] of DB::Any}
        when Eq
          {"#{compile_column(expr.column)} = #{placeholder}", [expr.value]}
        when NotEq
          {"#{compile_column(expr.column)} != #{placeholder}", [expr.value]}
        when Gt
          {"#{compile_column(expr.column)} > #{placeholder}", [expr.value]}
        when Gte
          {"#{compile_column(expr.column)} >= #{placeholder}", [expr.value]}
        when Lt
          {"#{compile_column(expr.column)} < #{placeholder}", [expr.value]}
        when Lte
          {"#{compile_column(expr.column)} <= #{placeholder}", [expr.value]}
        when Like
          {"#{compile_column(expr.column)} LIKE #{placeholder}", [expr.pattern.as(DB::Any)]}
        when ILike
          # SQLite doesn't have ILIKE, use LOWER() on both sides
          {"LOWER(#{compile_column(expr.column)}) LIKE LOWER(#{placeholder})", [expr.pattern.as(DB::Any)]}
        when In
          placeholders = expr.values.map { placeholder }.join(", ")
          {"#{compile_column(expr.column)} IN (#{placeholders})", expr.values}
        when Between
          {"#{compile_column(expr.column)} BETWEEN #{placeholder} AND #{placeholder}", [expr.min, expr.max]}
        when IsNull
          {"#{compile_column(expr.column)} IS NULL", [] of DB::Any}
        when IsNotNull
          {"#{compile_column(expr.column)} IS NOT NULL", [] of DB::Any}
        when And
          left_sql, left_params = compile_expression(expr.left)
          right_sql, right_params = compile_expression(expr.right)
          {"(#{left_sql} AND #{right_sql})", left_params + right_params}
        when Or
          left_sql, left_params = compile_expression(expr.left)
          right_sql, right_params = compile_expression(expr.right)
          {"(#{left_sql} OR #{right_sql})", left_params + right_params}
        when Not
          inner_sql, inner_params = compile_expression(expr.expression)
          {"NOT (#{inner_sql})", inner_params}
        when Raw
          {expr.sql, expr.params}
        else
          raise UnsupportedExpressionError.new(expr.class.name)
        end
      end

      private def compile_column(col : ColumnRef) : String
        "#{quote_identifier(col.table)}.#{quote_identifier(col.column)}"
      end

      private def compile_order(clauses : Array(OrderClause)) : String
        clauses.map do |c|
          dir = c.direction == :desc ? "DESC" : "ASC"
          "#{quote_identifier(c.table)}.#{quote_identifier(c.column)} #{dir}"
        end.join(", ")
      end
    end
  end
end
