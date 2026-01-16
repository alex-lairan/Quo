require "../introspection"
require "../connection_pool"

module Quo
  module Introspection
    # MySQL introspector
    # Queries information_schema for schema information
    class MySQLIntrospector < Introspector
      @pool : ConnectionPool
      @database : String?

      def initialize(@pool : ConnectionPool, @database : String? = nil)
      end

      def tables : Array(String)
        sql = <<-SQL
          SELECT table_name
          FROM information_schema.tables
          WHERE table_schema = DATABASE()
            AND table_type = 'BASE TABLE'
          ORDER BY table_name
        SQL

        results = [] of String
        @pool.checkout do |conn|
          conn.query(sql) do |rs|
            rs.each do
              results << rs.read(String)
            end
          end
        end
        results
      end

      def table(name : String) : IntrospectedTable?
        cols = columns(name)
        return nil if cols.empty?

        IntrospectedTable.new(
          name: name,
          columns: cols,
          indexes: indexes(name),
          foreign_keys: foreign_keys(name),
          primary_key_columns: cols.select(&.primary_key?).map(&.name)
        )
      end

      def columns(table_name : String) : Array(IntrospectedColumn)
        sql = <<-SQL
          SELECT
            column_name,
            data_type,
            is_nullable = 'YES' AS is_nullable,
            column_default,
            ordinal_position,
            column_key = 'PRI' AS is_primary_key
          FROM information_schema.columns
          WHERE table_schema = DATABASE()
            AND table_name = ?
          ORDER BY ordinal_position
        SQL

        results = [] of IntrospectedColumn
        @pool.checkout do |conn|
          conn.query(sql, table_name) do |rs|
            rs.each do
              results << IntrospectedColumn.new(
                name: rs.read(String),
                data_type: rs.read(String),
                nullable: rs.read(Int64) == 1, # MySQL returns 0/1 for boolean
                default_value: rs.read(String?),
                ordinal_position: rs.read(Int64).to_i32,
                primary_key: rs.read(Int64) == 1
              )
            end
          end
        end
        results
      end

      def indexes(table_name : String) : Array(IntrospectedIndex)
        sql = <<-SQL
          SELECT
            index_name,
            GROUP_CONCAT(column_name ORDER BY seq_in_index) AS columns,
            NOT non_unique AS is_unique,
            index_name = 'PRIMARY' AS is_primary,
            index_type
          FROM information_schema.statistics
          WHERE table_schema = DATABASE()
            AND table_name = ?
          GROUP BY index_name, non_unique, index_type
          ORDER BY index_name
        SQL

        results = [] of IntrospectedIndex
        @pool.checkout do |conn|
          conn.query(sql, table_name) do |rs|
            rs.each do
              index_name = rs.read(String)
              columns_str = rs.read(String)
              is_unique = rs.read(Int64) == 1
              is_primary = rs.read(Int64) == 1
              index_type = rs.read(String?)

              results << IntrospectedIndex.new(
                name: index_name,
                table_name: table_name,
                columns: columns_str.split(","),
                unique: is_unique,
                primary: is_primary,
                index_type: index_type
              )
            end
          end
        end
        results
      end

      def foreign_keys(table_name : String) : Array(ForeignKey)
        sql = <<-SQL
          SELECT
            constraint_name,
            table_name,
            column_name,
            referenced_table_name,
            referenced_column_name
          FROM information_schema.key_column_usage
          WHERE table_schema = DATABASE()
            AND table_name = ?
            AND referenced_table_name IS NOT NULL
        SQL

        # Get delete/update rules separately
        rules_sql = <<-SQL
          SELECT
            constraint_name,
            delete_rule,
            update_rule
          FROM information_schema.referential_constraints
          WHERE constraint_schema = DATABASE()
            AND table_name = ?
        SQL

        results = [] of ForeignKey
        rules = {} of String => {String?, String?}

        @pool.checkout do |conn|
          # First get the rules
          conn.query(rules_sql, table_name) do |rs|
            rs.each do
              name = rs.read(String)
              delete_rule = rs.read(String?)
              update_rule = rs.read(String?)
              rules[name] = {delete_rule, update_rule}
            end
          end

          # Then get the foreign keys
          conn.query(sql, table_name) do |rs|
            rs.each do
              name = rs.read(String)
              tbl = rs.read(String)
              col = rs.read(String)
              ref_table = rs.read(String)
              ref_col = rs.read(String)

              delete_rule, update_rule = rules[name]? || {nil, nil}

              results << ForeignKey.new(
                name: name,
                table_name: tbl,
                column_name: col,
                referenced_table: ref_table,
                referenced_column: ref_col,
                on_delete: delete_rule == "NO ACTION" ? nil : delete_rule,
                on_update: update_rule == "NO ACTION" ? nil : update_rule
              )
            end
          end
        end
        results
      end
    end
  end
end
