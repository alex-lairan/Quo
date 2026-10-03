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
      def compile(query : Query) : {String, Array(Quo::Value)}
        params = [] of Quo::Value

        sql = String.build do |str|
          # WITH clause (CTEs)
          unless query.cte_clauses.empty?
            has_recursive = query.cte_clauses.any?(&.recursive?)
            str << (has_recursive ? "WITH RECURSIVE " : "WITH ")

            cte_parts = query.cte_clauses.map do |cte|
              if cte.two_part_recursive?
                # Recursive CTE with base case UNION ALL recursive case
                base_sql, base_params = compile_for_set_operation(cte.base_query.not_nil!)
                params.concat(base_params)

                recursive_sql, recursive_params = compile_for_set_operation(cte.recursive_query.not_nil!)
                params.concat(recursive_params)

                "#{quote_identifier(cte.name)} AS (#{base_sql} UNION ALL #{recursive_sql})"
              else
                # Standard CTE
                cte_sql, cte_params = compile_for_set_operation(cte.query.not_nil!)
                params.concat(cte_params)
                "#{quote_identifier(cte.name)} AS (#{cte_sql})"
              end
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
              sql_part, expr_params = compile_expression(expr)
              params.concat(expr_params)
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
              sql_part, expr_params = compile_having_expression(expr)
              params.concat(expr_params)
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
            str << " LIMIT "
            str << placeholder
            params << limit.as(Quo::Value)
          end

          # OFFSET clause
          if offset = query.offset_value
            str << " OFFSET "
            str << placeholder
            params << offset.as(Quo::Value)
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

            # Compile the other query
            other_sql, other_params = compile_for_set_operation(set_op.query)
            str << other_sql
            params.concat(other_params)
          end
        end

        {sql, params}
      end

      # Compile a query for use in a set operation
      private def compile_for_set_operation(query : Query) : {String, Array(Quo::Value)}
        params = [] of Quo::Value

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

          # GROUP BY clause
          unless query.group_columns.empty?
            str << " GROUP BY "
            str << compile_group_by(query.group_columns)
          end

          # HAVING clause
          unless query.having_clauses.empty?
            str << " HAVING "
            having_parts = query.having_clauses.map do |expr|
              sql_part, expr_params = compile_having_expression(expr)
              params.concat(expr_params)
              sql_part
            end
            str << having_parts.join(" AND ")
          end
        end

        {sql, params}
      end

      # Compile COUNT query
      def compile_count(query : Query) : {String, Array(Quo::Value)}
        params = [] of Quo::Value

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
      # Execute query and return results
      def execute(sql : String, params : Array(Quo::Value)) : Quo::ResultSet
        connection = @connection || raise AdapterError.new("No database connection")
        results = [] of Quo::Row

        connection.query(sql, args: params) do |rs|
          rs.each do
            row = {} of String => Quo::Value
            rs.column_count.times do |i|
              col_name = rs.column_name(i)
              value = rs.read
              # SQLite returns basic types compatible with Quo::Value
              row[col_name] = value.as(Quo::Value)
            end
            results << row
          end
        end

        results
      end

      # Execute query and map to type T
      def execute(sql : String, params : Array(Quo::Value), as type : T.class) : Array(T) forall T
        connection = @connection || raise AdapterError.new("No database connection")
        connection.query_all(sql, args: params, as: type)
      end

      # Execute scalar query
      def execute_scalar(sql : String, params : Array(Quo::Value), as type : T.class) : T forall T
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
            parts << compile_select_column(col)
          end
        end

        # Aggregate functions
        query.aggregates.each do |agg|
          parts << compile_aggregate(agg)
        end

        parts.join(", ")
      end

      private def compile_select_column(col : SelectColumn) : String
        case col
        when ColumnRef
          "#{quote_identifier(col.table)}.#{quote_identifier(col.column)}"
        when AliasedColumn
          "#{quote_identifier(col.table)}.#{quote_identifier(col.original_column)} AS #{quote_identifier(col.alias_name)}"
        else
          raise UnsupportedExpressionError.new(col.class.name)
        end
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

      private def compile_having_expression(expr : HavingExpression) : {String, Array(Quo::Value)}
        case expr
        when AggregateGt
          agg_sql = compile_aggregate_for_having(expr.aggregate)
          {"#{agg_sql} > #{placeholder}", [expr.value]}
        when AggregateGte
          agg_sql = compile_aggregate_for_having(expr.aggregate)
          {"#{agg_sql} >= #{placeholder}", [expr.value]}
        when AggregateLt
          agg_sql = compile_aggregate_for_having(expr.aggregate)
          {"#{agg_sql} < #{placeholder}", [expr.value]}
        when AggregateLte
          agg_sql = compile_aggregate_for_having(expr.aggregate)
          {"#{agg_sql} <= #{placeholder}", [expr.value]}
        when AggregateEq
          agg_sql = compile_aggregate_for_having(expr.aggregate)
          {"#{agg_sql} = #{placeholder}", [expr.value]}
        when AggregateNotEq
          agg_sql = compile_aggregate_for_having(expr.aggregate)
          {"#{agg_sql} != #{placeholder}", [expr.value]}
        when AggregateBetween
          agg_sql = compile_aggregate_for_having(expr.aggregate)
          {"#{agg_sql} BETWEEN #{placeholder} AND #{placeholder}", [expr.min, expr.max]}
        when HavingAnd
          left_sql, left_params = compile_having_expression(expr.left)
          right_sql, right_params = compile_having_expression(expr.right)
          {"(#{left_sql} AND #{right_sql})", left_params + right_params}
        when HavingOr
          left_sql, left_params = compile_having_expression(expr.left)
          right_sql, right_params = compile_having_expression(expr.right)
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

      private def compile_expression(expr : Expression) : {String, Array(Quo::Value)}
        case expr
        when ColumnRef
          {compile_column(expr), [] of Quo::Value}
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
          {"#{compile_column(expr.column)} LIKE #{placeholder}", [expr.pattern.as(Quo::Value)]}
        when ILike
          # SQLite doesn't have ILIKE, use LOWER() on both sides
          {"LOWER(#{compile_column(expr.column)}) LIKE LOWER(#{placeholder})", [expr.pattern.as(Quo::Value)]}
        when In
          placeholders = expr.values.map { placeholder }.join(", ")
          {"#{compile_column(expr.column)} IN (#{placeholders})", expr.values}
        when Between
          {"#{compile_column(expr.column)} BETWEEN #{placeholder} AND #{placeholder}", [expr.min, expr.max]}
        when IsNull
          {"#{compile_column(expr.column)} IS NULL", [] of Quo::Value}
        when IsNotNull
          {"#{compile_column(expr.column)} IS NOT NULL", [] of Quo::Value}
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
      def compile_insert(query : InsertQuery) : {String, Array(Quo::Value)}
        raise QueryError.new("INSERT requires at least one row of values") if query.values_list.empty?

        # SQLite 3.35+ supports RETURNING, but we'll keep it compatible with older versions
        # If RETURNING is specified, warn that it may not work on older SQLite versions
        params = [] of Quo::Value

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
                params << row[col]
                placeholder
              else
                "NULL"  # SQLite uses NULL instead of DEFAULT for missing columns
              end
            end
            "(#{row_values.join(", ")})"
          end
          str << value_groups.join(", ")

          # RETURNING clause (SQLite 3.35+)
          unless query.returning_columns.empty?
            str << " RETURNING "
            str << query.returning_columns.map { |c| quote_identifier(c.column) }.join(", ")
          end
        end

        {sql, params}
      end

      # Execute INSERT and return affected rows
      def execute_insert(sql : String, params : Array(Quo::Value)) : Int64
        connection = @connection || raise AdapterError.new("No database connection")
        result = connection.exec(sql, args: params)
        result.rows_affected
      end

      # Compile UPDATE query
      def compile_update(query : UpdateQuery) : {String, Array(Quo::Value)}
        raise QueryError.new("UPDATE requires at least one SET value") if query.set_values.empty?

        params = [] of Quo::Value

        sql = String.build do |str|
          str << "UPDATE "
          str << quote_identifier(query.table)
          str << " SET "

          # SET clause
          set_parts = query.set_values.map do |col, value|
            params << value
            "#{quote_identifier(col)} = #{placeholder}"
          end
          str << set_parts.join(", ")

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

          # RETURNING clause (SQLite 3.35+)
          unless query.returning_columns.empty?
            str << " RETURNING "
            str << query.returning_columns.map { |c| quote_identifier(c.column) }.join(", ")
          end
        end

        {sql, params}
      end

      # Execute UPDATE and return affected rows
      def execute_update(sql : String, params : Array(Quo::Value)) : Int64
        connection = @connection || raise AdapterError.new("No database connection")
        result = connection.exec(sql, args: params)
        result.rows_affected
      end

      # Compile DELETE query
      def compile_delete(query : DeleteQuery) : {String, Array(Quo::Value)}
        params = [] of Quo::Value

        sql = String.build do |str|
          str << "DELETE FROM "
          str << quote_identifier(query.table)

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

          # RETURNING clause (SQLite 3.35+)
          unless query.returning_columns.empty?
            str << " RETURNING "
            str << query.returning_columns.map { |c| quote_identifier(c.column) }.join(", ")
          end
        end

        {sql, params}
      end

      # Execute DELETE and return affected rows
      def execute_delete(sql : String, params : Array(Quo::Value)) : Int64
        connection = @connection || raise AdapterError.new("No database connection")
        result = connection.exec(sql, args: params)
        result.rows_affected
      end

      # Execute a block within a database transaction
      # SQLite supports DEFERRED, IMMEDIATE, or EXCLUSIVE transactions
      # IsolationLevel maps to these: ReadUncommitted/ReadCommitted -> DEFERRED, RepeatableRead -> IMMEDIATE, Serializable -> EXCLUSIVE
      def transaction(isolation : IsolationLevel? = nil, &block : Transaction -> T) : T forall T
        connection = @connection || raise AdapterError.new("No database connection")

        # SQLite transaction modes
        tx_mode = if isolation
                    case isolation
                    in IsolationLevel::ReadUncommitted then "DEFERRED"
                    in IsolationLevel::ReadCommitted   then "DEFERRED"
                    in IsolationLevel::RepeatableRead  then "IMMEDIATE"
                    in IsolationLevel::Serializable    then "EXCLUSIVE"
                    end
                  else
                    "DEFERRED"
                  end

        connection.exec("BEGIN #{tx_mode}")

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
