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
      abstract def execute(sql : String, params : Array(DB::Any)) : Array(Hash(String, DB::Any))

      # Execute a query and map results to type T
      # Note: This needs to be implemented as a non-abstract method with generics
      def execute(sql : String, params : Array(DB::Any), as type : T.class) : Array(T) forall T
        raise AdapterError.new("Not implemented")
      end

      # Execute a scalar query (e.g., COUNT)
      def execute_scalar(sql : String, params : Array(DB::Any), as type : T.class) : T forall T
        raise AdapterError.new("Not implemented")
      end
    end
  end
end
