module Quo
  module Adapters
    # Test adapter for unit testing without a database
    # Compiles SQL like Postgres but doesn't execute queries
    class Test < Postgres
      def initialize
        super(nil)
      end

      # Override execute methods to raise error - tests should use to_sql
      def execute(sql : String, params : Array(DB::Any)) : Quo::ResultSet
        raise AdapterError.new("TestAdapter does not support query execution. Use to_sql for SQL generation tests.")
      end

      def execute(sql : String, params : Array(DB::Any), as type : T.class) : Array(T) forall T
        raise AdapterError.new("TestAdapter does not support query execution. Use to_sql for SQL generation tests.")
      end

      def execute_scalar(sql : String, params : Array(DB::Any), as type : T.class) : T forall T
        raise AdapterError.new("TestAdapter does not support query execution. Use to_sql for SQL generation tests.")
      end
    end
  end
end
