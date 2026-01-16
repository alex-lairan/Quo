require "./sqlite"
require "../connection_pool"
require "../logging"

module Quo
  module Adapters
    # SQLite adapter that uses connection pooling with logging integration
    class PooledSQLite < SQLite
      @pool : ConnectionPool

      def initialize(@pool : ConnectionPool)
        super(nil)
      end

      # Execute query and return results
      # Uses pool checkout and logging instrumentation
      def execute(sql : String, params : Array(DB::Any)) : Quo::ResultSet
        Logging.instrument(sql, params, :select) do
          results = [] of Quo::Row

          @pool.checkout do |conn|
            conn.query(sql, args: params) do |rs|
              rs.each do
                row = {} of String => Quo::Value
                rs.column_count.times do |i|
                  col_name = rs.column_name(i)
                  value = rs.read
                  row[col_name] = value.as(Quo::Value)
                end
                results << row
              end
            end
          end

          results
        end
      end

      # Execute query and map to type T
      def execute(sql : String, params : Array(DB::Any), as type : T.class) : Array(T) forall T
        Logging.instrument(sql, params, :select) do
          result = nil
          @pool.checkout do |conn|
            result = conn.query_all(sql, args: params, as: type)
          end
          result.not_nil!
        end
      end

      # Execute scalar query
      def execute_scalar(sql : String, params : Array(DB::Any), as type : T.class) : T forall T
        Logging.instrument(sql, params, :select) do
          result = uninitialized T
          @pool.checkout do |conn|
            result = conn.query_one(sql, args: params, as: type)
          end
          result
        end
      end

      # Execute INSERT and return affected rows
      def execute_insert(sql : String, params : Array(DB::Any)) : Int64
        Logging.instrument(sql, params, :insert) do
          rows = 0_i64
          @pool.checkout do |conn|
            rows = conn.exec(sql, args: params).rows_affected
          end
          rows
        end
      end

      # Execute UPDATE and return affected rows
      def execute_update(sql : String, params : Array(DB::Any)) : Int64
        Logging.instrument(sql, params, :update) do
          rows = 0_i64
          @pool.checkout do |conn|
            rows = conn.exec(sql, args: params).rows_affected
          end
          rows
        end
      end

      # Execute DELETE and return affected rows
      def execute_delete(sql : String, params : Array(DB::Any)) : Int64
        Logging.instrument(sql, params, :delete) do
          rows = 0_i64
          @pool.checkout do |conn|
            rows = conn.exec(sql, args: params).rows_affected
          end
          rows
        end
      end

      # Execute a block within a database transaction
      def transaction(isolation : IsolationLevel? = nil, &block : Transaction -> T) : T forall T
        @pool.checkout do |conn|
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

          conn.exec("BEGIN #{tx_mode}")

          begin
            # Create a transaction adapter that uses this connection
            tx_adapter = TransactionAdapter.new(conn)
            tx = Transaction.new(tx_adapter)
            result = yield tx
            conn.exec("COMMIT")
            result
          rescue ex
            conn.exec("ROLLBACK")
            raise ex
          end
        end
      end

      # Get pool statistics
      def pool_stats : PoolStats
        @pool.stats
      end

      # Check if pool is healthy
      def pool_healthy? : Bool
        @pool.healthy?
      end

      # Access underlying pool
      def pool : ConnectionPool
        @pool
      end

      # Internal adapter for transactions (uses single connection)
      private class TransactionAdapter < SQLite
        @conn : DB::Connection

        def initialize(@conn : DB::Connection)
          super(nil)
        end

        def execute(sql : String, params : Array(DB::Any)) : Quo::ResultSet
          Logging.instrument(sql, params, :select) do
            results = [] of Quo::Row

            @conn.query(sql, args: params) do |rs|
              rs.each do
                row = {} of String => Quo::Value
                rs.column_count.times do |i|
                  col_name = rs.column_name(i)
                  value = rs.read
                  row[col_name] = value.as(Quo::Value)
                end
                results << row
              end
            end

            results
          end
        end

        def execute(sql : String, params : Array(DB::Any), as type : T.class) : Array(T) forall T
          Logging.instrument(sql, params, :select) do
            @conn.query_all(sql, args: params, as: type)
          end
        end

        def execute_scalar(sql : String, params : Array(DB::Any), as type : T.class) : T forall T
          Logging.instrument(sql, params, :select) do
            @conn.query_one(sql, args: params, as: type)
          end
        end

        def execute_insert(sql : String, params : Array(DB::Any)) : Int64
          Logging.instrument(sql, params, :insert) do
            @conn.exec(sql, args: params).rows_affected
          end
        end

        def execute_update(sql : String, params : Array(DB::Any)) : Int64
          Logging.instrument(sql, params, :update) do
            @conn.exec(sql, args: params).rows_affected
          end
        end

        def execute_delete(sql : String, params : Array(DB::Any)) : Int64
          Logging.instrument(sql, params, :delete) do
            @conn.exec(sql, args: params).rows_affected
          end
        end

        def create_savepoint(name : Symbol) : Nil
          @conn.exec("SAVEPOINT #{name}")
        end

        def rollback_to_savepoint(name : Symbol) : Nil
          @conn.exec("ROLLBACK TO SAVEPOINT #{name}")
        end

        def release_savepoint(name : Symbol) : Nil
          @conn.exec("RELEASE SAVEPOINT #{name}")
        end
      end
    end
  end
end
