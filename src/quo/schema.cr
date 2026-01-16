require "./schema/column"
require "./schema/association"
require "./schema/registry"

module Quo
  # Schema definition for a database table
  # Defines columns, primary key, and associations
  class Schema
    getter table_name : Symbol
    getter columns : Hash(Symbol, Column)
    getter primary_key : Symbol?
    getter associations : Hash(Symbol, Association)

    def initialize(
      @table_name : Symbol,
      @columns : Hash(Symbol, Column) = {} of Symbol => Column,
      @primary_key : Symbol? = nil,
      @associations : Hash(Symbol, Association) = {} of Symbol => Association
    )
    end

    # Build a schema using the DSL
    def self.build(table_name : Symbol, &block) : Schema
      builder = SchemaBuilder.new(table_name)
      with builder yield
      builder.build
    end

    # Get a column by name
    def column(name : Symbol) : Column?
      @columns[name]?
    end

    # Check if a column exists
    def has_column?(name : Symbol) : Bool
      @columns.has_key?(name)
    end

    # Get an association by name
    def association(name : Symbol) : Association?
      @associations[name]?
    end

    # Check if an association exists
    def has_association?(name : Symbol) : Bool
      @associations.has_key?(name)
    end

    # Get all column names
    def column_names : Array(Symbol)
      @columns.keys
    end
  end

  # DSL builder for creating schemas
  class SchemaBuilder
    @table_name : Symbol
    @columns : Hash(Symbol, Column)
    @primary_key : Symbol?
    @associations : Hash(Symbol, Association)

    def initialize(@table_name : Symbol)
      @columns = {} of Symbol => Column
      @primary_key = nil
      @associations = {} of Symbol => Association
    end

    # Define the primary key column
    def primary_key(name : Symbol, type : T.class) forall T
      @primary_key = name
      @columns[name] = Column.new(name, T.to_s, primary_key: true)
    end

    # Define a regular column
    def column(name : Symbol, type : T.class, nullable : Bool = false, default : DB::Any? = nil) forall T
      @columns[name] = Column.new(name, T.to_s, nullable: nullable, default: default)
    end

    # Define a belongs_to association
    # The foreign key is on THIS table, pointing to the target table's key
    #
    # Examples:
    #   belongs_to :user, :user_id, :users
    #   belongs_to :user, :user_id, :users, :id
    #   belongs_to :subscription, :payment_provider_uuid, :stripe_subscriptions, :stripe_id
    def belongs_to(name : Symbol, foreign_key : Symbol, table : Symbol, key : Symbol = :id)
      @associations[name] = BelongsTo.new(name, foreign_key, table, key)
    end

    # Define a has_many association
    # The foreign key is on the TARGET table, pointing to this table's primary key
    #
    # Examples:
    #   has_many :invoices, :contract_id, :invoices
    #   has_many :invoices, :contract_id, :invoices, :id  # source_key defaults to :id
    def has_many(name : Symbol, foreign_key : Symbol, table : Symbol, source_key : Symbol = :id)
      @associations[name] = HasMany.new(name, foreign_key, table, source_key)
    end

    # Define a has_one association
    # Same as has_many but semantically indicates a single record
    #
    # Examples:
    #   has_one :profile, :user_id, :profiles
    def has_one(name : Symbol, foreign_key : Symbol, table : Symbol, source_key : Symbol = :id)
      @associations[name] = HasOne.new(name, foreign_key, table, source_key)
    end

    # Build the final Schema object
    def build : Schema
      Schema.new(@table_name, @columns, @primary_key, @associations)
    end
  end
end
