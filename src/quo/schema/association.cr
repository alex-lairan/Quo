module Quo
  # Base class for all association types
  abstract class Association
    getter name : Symbol
    getter foreign_key : Symbol
    getter target_table : Symbol
    getter target_key : Symbol

    def initialize(@name, @foreign_key, @target_table, @target_key = :id)
    end

    # Build join condition for this association
    # Returns {source_table, source_column, target_table, target_column}
    abstract def join_condition(source_table : Symbol) : {Symbol, Symbol, Symbol, Symbol}
  end

  # Represents a belongs_to association
  # The foreign key is on THIS table, pointing to the target's primary key
  #
  # Example:
  #   belongs_to :user, foreign_key: :user_id, table: :users
  #   # contracts.user_id = users.id
  #
  # Advanced example with custom target key:
  #   belongs_to :subscription, foreign_key: :payment_provider_uuid, table: :stripe_subscriptions, key: :stripe_id
  #   # insurance_policies.payment_provider_uuid = stripe_subscriptions.stripe_id
  class BelongsTo < Association
    def join_condition(source_table : Symbol) : {Symbol, Symbol, Symbol, Symbol}
      # source.foreign_key = target.target_key
      {source_table, @foreign_key, @target_table, @target_key}
    end
  end

  # Represents a has_many association
  # The foreign key is on the TARGET table, pointing to this table's primary key
  #
  # Example:
  #   has_many :invoices, foreign_key: :contract_id, table: :invoices
  #   # contracts.id = invoices.contract_id
  class HasMany < Association
    getter source_key : Symbol

    def initialize(name : Symbol, foreign_key : Symbol, target_table : Symbol, @source_key : Symbol = :id)
      super(name, foreign_key, target_table, foreign_key)
    end

    def join_condition(source_table : Symbol) : {Symbol, Symbol, Symbol, Symbol}
      # source.source_key = target.foreign_key
      {source_table, @source_key, @target_table, @foreign_key}
    end
  end

  # Represents a has_one association
  # Same as has_many but semantically indicates single record
  #
  # Example:
  #   has_one :profile, foreign_key: :user_id, table: :profiles
  #   # users.id = profiles.user_id
  class HasOne < Association
    getter source_key : Symbol

    def initialize(name : Symbol, foreign_key : Symbol, target_table : Symbol, @source_key : Symbol = :id)
      super(name, foreign_key, target_table, foreign_key)
    end

    def join_condition(source_table : Symbol) : {Symbol, Symbol, Symbol, Symbol}
      # source.source_key = target.foreign_key
      {source_table, @source_key, @target_table, @foreign_key}
    end
  end
end
