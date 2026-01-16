require "../introspection"
require "../connection_pool"

module Quo
  module Introspection
    # SQLite introspector
    # Uses PRAGMA commands to query schema information
    class SQLiteIntrospector < Introspector
      @pool : ConnectionPool

      def initialize(@pool : ConnectionPool)
      end

      def tables : Array(String)
        sql = <<-SQL
          SELECT name
          FROM sqlite_master
          WHERE type = 'table'
            AND name NOT LIKE 'sqlite_%'
          ORDER BY name
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
        results = [] of IntrospectedColumn

        @pool.checkout do |conn|
          conn.query("PRAGMA table_info(#{escape_identifier(table_name)})") do |rs|
            rs.each do
              cid = rs.read(Int64)
              name = rs.read(String)
              type = rs.read(String)
              notnull = rs.read(Int64)
              default = rs.read(String?)
              pk = rs.read(Int64)

              results << IntrospectedColumn.new(
                name: name,
                data_type: type,
                nullable: notnull == 0,
                default_value: default,
                primary_key: pk > 0,
                ordinal_position: cid.to_i32 + 1
              )
            end
          end
        end
        results
      end

      def indexes(table_name : String) : Array(IntrospectedIndex)
        results = [] of IntrospectedIndex

        @pool.checkout do |conn|
          # Get list of indexes
          conn.query("PRAGMA index_list(#{escape_identifier(table_name)})") do |rs|
            rs.each do
              seq = rs.read(Int64)
              name = rs.read(String)
              unique = rs.read(Int64)
              origin = rs.read(String)
              partial = rs.read(Int64)

              # Get columns for this index
              columns = [] of String
              conn.query("PRAGMA index_info(#{escape_identifier(name)})") do |idx_rs|
                idx_rs.each do
                  idx_rs.read(Int64) # seqno
                  idx_rs.read(Int64) # cid
                  col_name = idx_rs.read(String?)
                  columns << col_name if col_name
                end
              end

              results << IntrospectedIndex.new(
                name: name,
                table_name: table_name,
                columns: columns,
                unique: unique == 1,
                primary: origin == "pk",
                index_type: nil
              )
            end
          end
        end
        results
      end

      def foreign_keys(table_name : String) : Array(ForeignKey)
        results = [] of ForeignKey

        @pool.checkout do |conn|
          conn.query("PRAGMA foreign_key_list(#{escape_identifier(table_name)})") do |rs|
            rs.each do
              id = rs.read(Int64)
              seq = rs.read(Int64)
              table = rs.read(String)
              from = rs.read(String)
              to = rs.read(String)
              on_update = rs.read(String)
              on_delete = rs.read(String)
              match = rs.read(String)

              results << ForeignKey.new(
                name: "fk_#{table_name}_#{from}_#{id}",
                table_name: table_name,
                column_name: from,
                referenced_table: table,
                referenced_column: to,
                on_delete: on_delete == "NO ACTION" ? nil : on_delete,
                on_update: on_update == "NO ACTION" ? nil : on_update
              )
            end
          end
        end
        results
      end

      private def escape_identifier(name : String) : String
        # Simple escaping for SQLite identifiers
        "\"#{name.gsub("\"", "\"\"")}\""
      end
    end
  end
end
