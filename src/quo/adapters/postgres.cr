require "db"

module Quo
  module Adapters
    # PostgreSQL adapter for SQL generation and execution
    class Postgres < Adapter
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
        param_index = 0

        sql = String.build do |str|
          # WITH clause (CTEs)
          unless query.cte_clauses.empty?
            has_recursive = query.cte_clauses.any?(&.recursive?)
            str << (has_recursive ? "WITH RECURSIVE " : "WITH ")

            cte_parts = query.cte_clauses.map do |cte|
              cte_sql, cte_params = compile_for_set_operation(cte.query, param_index)
              params.concat(cte_params)
              param_index += cte_params.size
              "#{quote_identifier(cte.name)} AS (#{cte_sql})"
            end
            str << cte_parts.join(", ")
            str << " "
          end

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
              sql_part, expr_params = compile_expression(expr, param_index)
              params.concat(expr_params)
              param_index += expr_params.size
              sql_part
            end
            str << where_parts.join(" AND ")
          end

          # GROUP BY clause
          unless query.group_columns.empty?
            str << " GROUP BY "
            str << compile_group_by(query.group_columns)
          end

          # HAVING clause
          unless query.having_clauses.empty?
            str << " HAVING "
            having_parts = query.having_clauses.map do |expr|
              sql_part, expr_params = compile_having_expression(expr, param_index)
              params.concat(expr_params)
              param_index += expr_params.size
              sql_part
            end
            str << having_parts.join(" AND ")
          end

          # ORDER BY clause
          unless query.order_clauses.empty?
            str << " ORDER BY "
            str << compile_order(query.order_clauses)
          end

          # LIMIT clause
          if limit = query.limit_value
            param_index += 1
            str << " LIMIT "
            str << placeholder(param_index)
            params << limit.as(DB::Any)
          end

          # OFFSET clause
          if offset = query.offset_value
            param_index += 1
            str << " OFFSET "
            str << placeholder(param_index)
            params << offset.as(DB::Any)
          end

          # Set operations (UNION, INTERSECT, EXCEPT)
          query.set_operations.each do |set_op|
            op_sql = case set_op.operation_type
                     in SetOperationType::Union        then "UNION"
                     in SetOperationType::UnionAll     then "UNION ALL"
                     in SetOperationType::Intersect    then "INTERSECT"
                     in SetOperationType::IntersectAll then "INTERSECT ALL"
                     in SetOperationType::Except       then "EXCEPT"
                     in SetOperationType::ExceptAll    then "EXCEPT ALL"
                     end
            str << " " << op_sql << " "

            # Compile the other query and adjust parameter indices
            other_sql, other_params = compile_for_set_operation(set_op.query, param_index)
            str << other_sql
            params.concat(other_params)
            param_index += other_params.size
          end
        end

        {sql, params}
      end

      # Compile a query for use in a set operation (without ORDER BY, LIMIT, OFFSET at this level)
      private def compile_for_set_operation(query : Query, start_index : Int32) : {String, Array(DB::Any)}
        params = [] of DB::Any
        param_index = start_index

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
              sql_part, expr_params = compile_expression(expr, param_index)
              params.concat(expr_params)
              param_index += expr_params.size
              sql_part
            end
            str << where_parts.join(" AND ")
          end

          # GROUP BY clause
          unless query.group_columns.empty?
            str << " GROUP BY "
            str << compile_group_by(query.group_columns)
          end

          # HAVING clause
          unless query.having_clauses.empty?
            str << " HAVING "
            having_parts = query.having_clauses.map do |expr|
              sql_part, expr_params = compile_having_expression(expr, param_index)
              params.concat(expr_params)
              param_index += expr_params.size
              sql_part
            end
            str << having_parts.join(" AND ")
          end
        end

        {sql, params}
      end

      # Compile COUNT query
      def compile_count(query : Query) : {String, Array(DB::Any)}
        params = [] of DB::Any
        param_index = 0

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
              sql_part, expr_params = compile_expression(expr, param_index)
              params.concat(expr_params)
              param_index += expr_params.size
              sql_part
            end
            str << where_parts.join(" AND ")
          end
        end

        {sql, params}
      end

      # Quote identifier with double quotes (Postgres style)
      def quote_identifier(name : Symbol) : String
        "\"#{name}\""
      end

      # Postgres uses $1, $2, etc. for parameters
      def placeholder(index : Int32) : String
        "$#{index}"
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
              value = rs.read
              # Cast PostgreSQL native types to DB::Any compatible types
              row[col_name] = convert_pg_value(value)
            end
            results << row
          end
        end

        results
      end

      # Convert PG-specific types to DB::Any compatible types
      private def convert_pg_value(value) : DB::Any
        case value
        when Bool, Int32, Int64, Float32, Float64, String, Time, Nil
          value.as(DB::Any)
        when Slice(UInt8)
          value.as(DB::Any)
        when Int16
          value.to_i64.as(DB::Any)
        when UInt32, UInt64
          value.to_i64.as(DB::Any)
        when PG::Numeric
          value.to_f64.as(DB::Any)
        else
          # For other PG-specific types (UUID, JSON, Geo, etc.), convert to string
          value.to_s.as(DB::Any)
        end
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
        parts = [] of String

        # Regular columns
        if query.select_columns.empty? && query.aggregates.empty?
          parts << "#{quote_identifier(query.table)}.*"
        else
          query.select_columns.each do |col|
            parts << "#{quote_identifier(col.table)}.#{quote_identifier(col.column)}"
          end
        end

        # Aggregate functions
        query.aggregates.each do |agg|
          parts << compile_aggregate(agg)
        end

        parts.join(", ")
      end

      private def compile_aggregate(agg : Aggregate) : String
        func_name = case agg.function
                    in AggregateFunction::Count then "COUNT"
                    in AggregateFunction::Sum   then "SUM"
                    in AggregateFunction::Avg   then "AVG"
                    in AggregateFunction::Min   then "MIN"
                    in AggregateFunction::Max   then "MAX"
                    end

        inner = if col = agg.column
                  col_str = "#{quote_identifier(col.table)}.#{quote_identifier(col.column)}"
                  agg.distinct? ? "DISTINCT #{col_str}" : col_str
                else
                  "*"
                end

        result = "#{func_name}(#{inner})"

        if alias_name = agg.alias_name
          result += " AS #{quote_identifier(alias_name)}"
        end

        result
      end

      private def compile_group_by(columns : Array(GroupColumn)) : String
        columns.map do |col|
          "#{quote_identifier(col.table)}.#{quote_identifier(col.column)}"
        end.join(", ")
      end

      private def compile_having_expression(expr : HavingExpression, start_index : Int32) : {String, Array(DB::Any)}
        case expr
        when AggregateGt
          agg_sql = compile_aggregate_for_having(expr.aggregate)
          {"#{agg_sql} > #{placeholder(start_index + 1)}", [expr.value]}
        when AggregateGte
          agg_sql = compile_aggregate_for_having(expr.aggregate)
          {"#{agg_sql} >= #{placeholder(start_index + 1)}", [expr.value]}
        when AggregateLt
          agg_sql = compile_aggregate_for_having(expr.aggregate)
          {"#{agg_sql} < #{placeholder(start_index + 1)}", [expr.value]}
        when AggregateLte
          agg_sql = compile_aggregate_for_having(expr.aggregate)
          {"#{agg_sql} <= #{placeholder(start_index + 1)}", [expr.value]}
        when AggregateEq
          agg_sql = compile_aggregate_for_having(expr.aggregate)
          {"#{agg_sql} = #{placeholder(start_index + 1)}", [expr.value]}
        when AggregateNotEq
          agg_sql = compile_aggregate_for_having(expr.aggregate)
          {"#{agg_sql} != #{placeholder(start_index + 1)}", [expr.value]}
        when AggregateBetween
          agg_sql = compile_aggregate_for_having(expr.aggregate)
          {"#{agg_sql} BETWEEN #{placeholder(start_index + 1)} AND #{placeholder(start_index + 2)}", [expr.min, expr.max]}
        when HavingAnd
          left_sql, left_params = compile_having_expression(expr.left, start_index)
          right_sql, right_params = compile_having_expression(expr.right, start_index + left_params.size)
          {"(#{left_sql} AND #{right_sql})", left_params + right_params}
        when HavingOr
          left_sql, left_params = compile_having_expression(expr.left, start_index)
          right_sql, right_params = compile_having_expression(expr.right, start_index + left_params.size)
          {"(#{left_sql} OR #{right_sql})", left_params + right_params}
        else
          raise UnsupportedExpressionError.new(expr.class.name)
        end
      end

      private def compile_aggregate_for_having(agg : Aggregate) : String
        func_name = case agg.function
                    in AggregateFunction::Count then "COUNT"
                    in AggregateFunction::Sum   then "SUM"
                    in AggregateFunction::Avg   then "AVG"
                    in AggregateFunction::Min   then "MIN"
                    in AggregateFunction::Max   then "MAX"
                    end

        inner = if col = agg.column
                  col_str = "#{quote_identifier(col.table)}.#{quote_identifier(col.column)}"
                  agg.distinct? ? "DISTINCT #{col_str}" : col_str
                else
                  "*"
                end

        "#{func_name}(#{inner})"
      end

      private def compile_join(join : Join) : String
        type_str = case join.type
                   in JoinType::Inner then "INNER JOIN"
                   in JoinType::Left  then "LEFT JOIN"
                   in JoinType::Right then "RIGHT JOIN"
                   in JoinType::Full  then "FULL JOIN"
                   end

        cond = join.condition
        " #{type_str} #{quote_identifier(join.table)} ON " \
        "#{quote_identifier(cond.left_table)}.#{quote_identifier(cond.left_column)} = " \
        "#{quote_identifier(cond.right_table)}.#{quote_identifier(cond.right_column)}"
      end

      private def compile_expression(expr : Expression, start_index : Int32) : {String, Array(DB::Any)}
        case expr
        when ColumnRef
          {compile_column(expr), [] of DB::Any}
        when Eq
          {"#{compile_column(expr.column)} = #{placeholder(start_index + 1)}", [expr.value]}
        when NotEq
          {"#{compile_column(expr.column)} != #{placeholder(start_index + 1)}", [expr.value]}
        when Gt
          {"#{compile_column(expr.column)} > #{placeholder(start_index + 1)}", [expr.value]}
        when Gte
          {"#{compile_column(expr.column)} >= #{placeholder(start_index + 1)}", [expr.value]}
        when Lt
          {"#{compile_column(expr.column)} < #{placeholder(start_index + 1)}", [expr.value]}
        when Lte
          {"#{compile_column(expr.column)} <= #{placeholder(start_index + 1)}", [expr.value]}
        when Like
          {"#{compile_column(expr.column)} LIKE #{placeholder(start_index + 1)}", [expr.pattern.as(DB::Any)]}
        when ILike
          {"#{compile_column(expr.column)} ILIKE #{placeholder(start_index + 1)}", [expr.pattern.as(DB::Any)]}
        when In
          placeholders = expr.values.map_with_index { |_, i| placeholder(start_index + 1 + i) }.join(", ")
          {"#{compile_column(expr.column)} IN (#{placeholders})", expr.values}
        when Between
          {"#{compile_column(expr.column)} BETWEEN #{placeholder(start_index + 1)} AND #{placeholder(start_index + 2)}", [expr.min, expr.max]}
        when IsNull
          {"#{compile_column(expr.column)} IS NULL", [] of DB::Any}
        when IsNotNull
          {"#{compile_column(expr.column)} IS NOT NULL", [] of DB::Any}
        when And
          left_sql, left_params = compile_expression(expr.left, start_index)
          right_sql, right_params = compile_expression(expr.right, start_index + left_params.size)
          {"(#{left_sql} AND #{right_sql})", left_params + right_params}
        when Or
          left_sql, left_params = compile_expression(expr.left, start_index)
          right_sql, right_params = compile_expression(expr.right, start_index + left_params.size)
          {"(#{left_sql} OR #{right_sql})", left_params + right_params}
        when Not
          inner_sql, inner_params = compile_expression(expr.expression, start_index)
          {"NOT (#{inner_sql})", inner_params}
        when Raw
          {expr.sql, expr.params}
        when InSubquery
          sub_sql, sub_params = compile(expr.subquery.query)
          {"#{compile_column(expr.column)} IN (#{sub_sql})", sub_params}
        when NotInSubquery
          sub_sql, sub_params = compile(expr.subquery.query)
          {"#{compile_column(expr.column)} NOT IN (#{sub_sql})", sub_params}
        when Exists
          sub_sql, sub_params = compile(expr.subquery.query)
          {"EXISTS (#{sub_sql})", sub_params}
        when NotExists
          sub_sql, sub_params = compile(expr.subquery.query)
          {"NOT EXISTS (#{sub_sql})", sub_params}
        when ScalarEq
          sub_sql, sub_params = compile(expr.subquery.query)
          {"#{compile_column(expr.column)} = (#{sub_sql})", sub_params}
        when ScalarGt
          sub_sql, sub_params = compile(expr.subquery.query)
          {"#{compile_column(expr.column)} > (#{sub_sql})", sub_params}
        when ScalarGte
          sub_sql, sub_params = compile(expr.subquery.query)
          {"#{compile_column(expr.column)} >= (#{sub_sql})", sub_params}
        when ScalarLt
          sub_sql, sub_params = compile(expr.subquery.query)
          {"#{compile_column(expr.column)} < (#{sub_sql})", sub_params}
        when ScalarLte
          sub_sql, sub_params = compile(expr.subquery.query)
          {"#{compile_column(expr.column)} <= (#{sub_sql})", sub_params}
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

      # Compile INSERT query
      def compile_insert(query : InsertQuery) : {String, Array(DB::Any)}
        raise QueryError.new("INSERT requires at least one row of values") if query.values_list.empty?

        params = [] of DB::Any
        param_index = 0

        # Get all unique columns from all rows
        all_columns = query.values_list.flat_map(&.keys).uniq

        sql = String.build do |str|
          str << "INSERT INTO "
          str << quote_identifier(query.table)
          str << " ("
          str << all_columns.map { |c| quote_identifier(c) }.join(", ")
          str << ") VALUES "

          # Generate VALUES for each row
          value_groups = query.values_list.map do |row|
            row_values = all_columns.map do |col|
              if row.has_key?(col)
                param_index += 1
                params << row[col]
                placeholder(param_index)
              else
                "DEFAULT"
              end
            end
            "(#{row_values.join(", ")})"
          end
          str << value_groups.join(", ")

          # RETURNING clause (PostgreSQL specific)
          unless query.returning_columns.empty?
            str << " RETURNING "
            str << query.returning_columns.map { |c| quote_identifier(c.column) }.join(", ")
          end
        end

        {sql, params}
      end

      # Execute INSERT and return affected rows
      def execute_insert(sql : String, params : Array(DB::Any)) : Int64
        connection = @connection || raise AdapterError.new("No database connection")
        result = connection.exec(sql, args: params)
        result.rows_affected
      end

      # Compile UPDATE query
      def compile_update(query : UpdateQuery) : {String, Array(DB::Any)}
        raise QueryError.new("UPDATE requires at least one SET value") if query.set_values.empty?

        params = [] of DB::Any
        param_index = 0

        sql = String.build do |str|
          str << "UPDATE "
          str << quote_identifier(query.table)
          str << " SET "

          # SET clause
          set_parts = query.set_values.map do |col, value|
            param_index += 1
            params << value
            "#{quote_identifier(col)} = #{placeholder(param_index)}"
          end
          str << set_parts.join(", ")

          # WHERE clause
          unless query.where_clauses.empty?
            str << " WHERE "
            where_parts = query.where_clauses.map do |expr|
              sql_part, expr_params = compile_expression(expr, param_index)
              params.concat(expr_params)
              param_index += expr_params.size
              sql_part
            end
            str << where_parts.join(" AND ")
          end

          # RETURNING clause (PostgreSQL specific)
          unless query.returning_columns.empty?
            str << " RETURNING "
            str << query.returning_columns.map { |c| quote_identifier(c.column) }.join(", ")
          end
        end

        {sql, params}
      end

      # Execute UPDATE and return affected rows
      def execute_update(sql : String, params : Array(DB::Any)) : Int64
        connection = @connection || raise AdapterError.new("No database connection")
        result = connection.exec(sql, args: params)
        result.rows_affected
      end

      # Compile DELETE query
      def compile_delete(query : DeleteQuery) : {String, Array(DB::Any)}
        params = [] of DB::Any
        param_index = 0

        sql = String.build do |str|
          str << "DELETE FROM "
          str << quote_identifier(query.table)

          # WHERE clause
          unless query.where_clauses.empty?
            str << " WHERE "
            where_parts = query.where_clauses.map do |expr|
              sql_part, expr_params = compile_expression(expr, param_index)
              params.concat(expr_params)
              param_index += expr_params.size
              sql_part
            end
            str << where_parts.join(" AND ")
          end

          # RETURNING clause (PostgreSQL specific)
          unless query.returning_columns.empty?
            str << " RETURNING "
            str << query.returning_columns.map { |c| quote_identifier(c.column) }.join(", ")
          end
        end

        {sql, params}
      end

      # Execute DELETE and return affected rows
      def execute_delete(sql : String, params : Array(DB::Any)) : Int64
        connection = @connection || raise AdapterError.new("No database connection")
        result = connection.exec(sql, args: params)
        result.rows_affected
      end

      # Execute a block within a database transaction
      def transaction(isolation : IsolationLevel? = nil, &block : Transaction -> T) : T forall T
        connection = @connection || raise AdapterError.new("No database connection")

        # Start transaction with optional isolation level
        if isolation
          isolation_sql = case isolation
                          in IsolationLevel::ReadUncommitted then "READ UNCOMMITTED"
                          in IsolationLevel::ReadCommitted   then "READ COMMITTED"
                          in IsolationLevel::RepeatableRead  then "REPEATABLE READ"
                          in IsolationLevel::Serializable    then "SERIALIZABLE"
                          end
          connection.exec("BEGIN TRANSACTION ISOLATION LEVEL #{isolation_sql}")
        else
          connection.exec("BEGIN")
        end

        begin
          tx = Transaction.new(self)
          result = yield tx
          connection.exec("COMMIT")
          result
        rescue ex
          connection.exec("ROLLBACK")
          raise ex
        end
      end

      # Create a savepoint
      def create_savepoint(name : Symbol) : Nil
        connection = @connection || raise AdapterError.new("No database connection")
        connection.exec("SAVEPOINT #{name}")
      end

      # Rollback to a savepoint
      def rollback_to_savepoint(name : Symbol) : Nil
        connection = @connection || raise AdapterError.new("No database connection")
        connection.exec("ROLLBACK TO SAVEPOINT #{name}")
      end

      # Release a savepoint
      def release_savepoint(name : Symbol) : Nil
        connection = @connection || raise AdapterError.new("No database connection")
        connection.exec("RELEASE SAVEPOINT #{name}")
      end
    end
  end
end
