module Quo
  # Represents a column definition in a schema
  struct Column
    getter name : Symbol
    getter type_name : String
    getter? primary_key : Bool
    getter? nullable : Bool
    getter default : DB::Any?

    def initialize(
      @name : Symbol,
      @type_name : String,
      @primary_key : Bool = false,
      @nullable : Bool = false,
      @default : DB::Any? = nil
    )
    end

    # Create a column with a Crystal type
    def self.new(name : Symbol, type : T.class, **options) forall T
      new(name, T.to_s, **options)
    end
  end
end
