module Quo
  # Base class for repositories using Quo relations
  #
  # Provides:
  # - Access to the adapter for write operations
  # - `relation` macro to declare relation accessors
  #
  # Example:
  #   class QuoAccountRepository < Quo::Repository
  #     include AccountRepositoryInterface
  #
  #     relation :accounts, AccountsRelation
  #     relation :password_hashes, PasswordHashesRelation
  #
  #     def find_by_email(email : String) : Account?
  #       accounts.active.by_email(email).first.try { |row| map(row) }
  #     end
  #   end
  abstract class Repository
    getter adapter : Adapters::Adapter

    def initialize(@adapter : Adapters::Adapter)
    end

    # Macro to declare a relation accessor
    # Creates a method that returns a new instance of the relation class
    #
    # Usage: relation :accounts, AccountsRelation
    macro relation(name, klass)
      def {{name.id}} : {{klass}}
        {{klass}}.new(@adapter)
      end
    end
  end
end
