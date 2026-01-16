module Quo
  # Transaction isolation levels
  enum IsolationLevel
    ReadUncommitted
    ReadCommitted
    RepeatableRead
    Serializable
  end

  # Represents an active database transaction
  # Provides methods to execute queries within the transaction
  class Transaction
    @adapter : Adapters::Adapter
    @savepoint_counter : Int32 = 0

    def initialize(@adapter)
    end

    # Create a new Query within this transaction
    def query(table : Symbol) : Query
      Query.new(table, @adapter)
    end

    # Alias for query
    def [](table : Symbol) : Query
      query(table)
    end

    # Create a new InsertQuery within this transaction
    def insert(table : Symbol) : InsertQuery
      InsertQuery.new(table, @adapter)
    end

    # Create a new UpdateQuery within this transaction
    def update(table : Symbol) : UpdateQuery
      UpdateQuery.new(table, @adapter)
    end

    # Create a new DeleteQuery within this transaction
    def delete(table : Symbol) : DeleteQuery
      DeleteQuery.new(table, @adapter)
    end

    # Execute raw SQL within the transaction
    def execute(sql : String, params : Array(DB::Any) = [] of DB::Any) : Array(Hash(String, DB::Any))
      @adapter.execute(sql, params)
    end

    # Execute raw SQL and return scalar value
    def execute_scalar(sql : String, params : Array(DB::Any), as type : T.class) : T forall T
      @adapter.execute_scalar(sql, params, as: type)
    end

    # Create a savepoint and execute block
    # If block raises, rollback to savepoint and re-raise
    def savepoint(name : Symbol? = nil, &block)
      savepoint_name = name || generate_savepoint_name
      @adapter.create_savepoint(savepoint_name)
      begin
        yield
      rescue ex
        @adapter.rollback_to_savepoint(savepoint_name)
        raise ex
      end
      @adapter.release_savepoint(savepoint_name)
    end

    private def generate_savepoint_name : Symbol
      @savepoint_counter += 1
      :"quo_sp_#{@savepoint_counter}"
    end
  end
end
