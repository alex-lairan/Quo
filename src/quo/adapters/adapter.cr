module Quo
  module Adapters
    # Abstract base adapter - defines the interface for SQL generation and execution
    abstract class Adapter
      # Compile a Query into SQL string and parameters
      abstract def compile(query : Query) : {String, Array(DB::Any)}

      # Compile a COUNT query
      abstract def compile_count(query : Query) : {String, Array(DB::Any)}

      # Quote an identifier (table or column name)
      abstract def quote_identifier(name : Symbol) : String

      # Generate a parameter placeholder for the given index (1-based)
      abstract def placeholder(index : Int32) : String

      # Execute a query and return results as array of hashes
      # Returns Quo::ResultSet which preserves rich types (UUID, PG::Numeric, etc.)
      abstract def execute(sql : String, params : Array(DB::Any)) : Quo::ResultSet

      # Execute a query and map results to type T
      # Note: This needs to be implemented as a non-abstract method with generics
      def execute(sql : String, params : Array(DB::Any), as type : T.class) : Array(T) forall T
        raise AdapterError.new("Not implemented")
      end

      # Execute a scalar query (e.g., COUNT)
      def execute_scalar(sql : String, params : Array(DB::Any), as type : T.class) : T forall T
        raise AdapterError.new("Not implemented")
      end

      # Compile an InsertQuery into SQL string and parameters
      def compile_insert(query : InsertQuery) : {String, Array(DB::Any)}
        raise AdapterError.new("Not implemented")
      end

      # Compile an UpdateQuery into SQL string and parameters
      def compile_update(query : UpdateQuery) : {String, Array(DB::Any)}
        raise AdapterError.new("Not implemented")
      end

      # Compile a DeleteQuery into SQL string and parameters
      def compile_delete(query : DeleteQuery) : {String, Array(DB::Any)}
        raise AdapterError.new("Not implemented")
      end

      # Execute an INSERT and return number of affected rows
      def execute_insert(sql : String, params : Array(DB::Any)) : Int64
        raise AdapterError.new("Not implemented")
      end

      # Execute an UPDATE and return number of affected rows
      def execute_update(sql : String, params : Array(DB::Any)) : Int64
        raise AdapterError.new("Not implemented")
      end

      # Execute a DELETE and return number of affected rows
      def execute_delete(sql : String, params : Array(DB::Any)) : Int64
        raise AdapterError.new("Not implemented")
      end

      # Execute a block within a database transaction
      # Commits on success, rolls back on exception
      def transaction(isolation : IsolationLevel? = nil, &block : Transaction -> T) : T forall T
        raise AdapterError.new("Transactions not implemented for this adapter")
      end

      # Create a savepoint within a transaction
      def create_savepoint(name : Symbol) : Nil
        raise AdapterError.new("Savepoints not implemented for this adapter")
      end

      # Rollback to a savepoint
      def rollback_to_savepoint(name : Symbol) : Nil
        raise AdapterError.new("Savepoints not implemented for this adapter")
      end

      # Release (commit) a savepoint
      def release_savepoint(name : Symbol) : Nil
        raise AdapterError.new("Savepoints not implemented for this adapter")
      end
    end
  end
end
