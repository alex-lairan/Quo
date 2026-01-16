require "../introspection"
require "../connection_pool"

module Quo
  module Introspection
    # PostgreSQL introspector
    # Queries information_schema and pg_* system catalogs
    class PostgresIntrospector < Introspector
      @pool : ConnectionPool

      def initialize(@pool : ConnectionPool)
      end

      def tables : Array(String)
        sql = <<-SQL
          SELECT table_name
          FROM information_schema.tables
          WHERE table_schema = 'public'
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
            c.column_name,
            c.data_type,
            c.is_nullable = 'YES' AS is_nullable,
            c.column_default,
            c.ordinal_position,
            COALESCE(
              (SELECT true
               FROM information_schema.table_constraints tc
               JOIN information_schema.key_column_usage kcu
                 ON tc.constraint_name = kcu.constraint_name
                 AND tc.table_schema = kcu.table_schema
               WHERE tc.table_name = c.table_name
                 AND tc.constraint_type = 'PRIMARY KEY'
                 AND kcu.column_name = c.column_name
               LIMIT 1),
              false
            ) AS is_primary_key
          FROM information_schema.columns c
          WHERE c.table_schema = 'public'
            AND c.table_name = $1
          ORDER BY c.ordinal_position
        SQL

        results = [] of IntrospectedColumn
        @pool.checkout do |conn|
          conn.query(sql, table_name) do |rs|
            rs.each do
              results << IntrospectedColumn.new(
                name: rs.read(String),
                data_type: rs.read(String),
                nullable: rs.read(Bool),
                default_value: rs.read(String?),
                ordinal_position: rs.read(Int32),
                primary_key: rs.read(Bool)
              )
            end
          end
        end
        results
      end

      def indexes(table_name : String) : Array(IntrospectedIndex)
        sql = <<-SQL
          SELECT
            i.relname AS index_name,
            t.relname AS table_name,
            array_agg(a.attname ORDER BY array_position(ix.indkey, a.attnum)) AS columns,
            ix.indisunique AS is_unique,
            ix.indisprimary AS is_primary,
            am.amname AS index_type
          FROM pg_index ix
          JOIN pg_class i ON i.oid = ix.indexrelid
          JOIN pg_class t ON t.oid = ix.indrelid
          JOIN pg_namespace n ON n.oid = t.relnamespace
          JOIN pg_am am ON am.oid = i.relam
          JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(ix.indkey)
          WHERE n.nspname = 'public'
            AND t.relname = $1
          GROUP BY i.relname, t.relname, ix.indisunique, ix.indisprimary, am.amname
          ORDER BY i.relname
        SQL

        results = [] of IntrospectedIndex
        @pool.checkout do |conn|
          conn.query(sql, table_name) do |rs|
            rs.each do
              results << IntrospectedIndex.new(
                name: rs.read(String),
                table_name: rs.read(String),
                columns: rs.read(Array(String)),
                unique: rs.read(Bool),
                primary: rs.read(Bool),
                index_type: rs.read(String?)
              )
            end
          end
        end
        results
      end

      def foreign_keys(table_name : String) : Array(ForeignKey)
        sql = <<-SQL
          SELECT
            tc.constraint_name,
            tc.table_name,
            kcu.column_name,
            ccu.table_name AS referenced_table,
            ccu.column_name AS referenced_column,
            rc.delete_rule,
            rc.update_rule
          FROM information_schema.table_constraints tc
          JOIN information_schema.key_column_usage kcu
            ON tc.constraint_name = kcu.constraint_name
            AND tc.table_schema = kcu.table_schema
          JOIN information_schema.constraint_column_usage ccu
            ON ccu.constraint_name = tc.constraint_name
            AND ccu.table_schema = tc.table_schema
          JOIN information_schema.referential_constraints rc
            ON rc.constraint_name = tc.constraint_name
            AND rc.constraint_schema = tc.table_schema
          WHERE tc.constraint_type = 'FOREIGN KEY'
            AND tc.table_name = $1
        SQL

        results = [] of ForeignKey
        @pool.checkout do |conn|
          conn.query(sql, table_name) do |rs|
            rs.each do
              results << ForeignKey.new(
                name: rs.read(String),
                table_name: rs.read(String),
                column_name: rs.read(String),
                referenced_table: rs.read(String),
                referenced_column: rs.read(String),
                on_delete: rs.read(String?),
                on_update: rs.read(String?)
              )
            end
          end
        end
        results
      end
    end
  end
end
