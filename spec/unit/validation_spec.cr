require "../spec_helper"

# Test relation with full column definitions for validation testing
class ValidatedContractsRelation < Quo::Relation
  schema :validated_contracts do
    primary_key :id, String
    column :reference, String
    column :status, String
    column :amount_cents, Int64
    column :discount_percent, Float64
    column :active, Bool
    column :user_id, String
    column :created_at, Time

    belongs_to :user, :user_id, :validated_users
  end
end

class ValidatedUsersRelation < Quo::Relation
  schema :validated_users do
    primary_key :id, String
    column :name, String
    column :email, String
    column :age, Int32
    column :active, Bool
  end
end

describe "Schema Validation" do
  describe "select validation" do
    it "allows valid columns" do
      relation = ValidatedContractsRelation.new(test_adapter)
        .select(validated_contracts: [:id, :reference, :status])

      sql, _ = relation.to_sql
      sql.should contain(%("validated_contracts"."id"))
    end

    it "raises error for invalid column" do
      relation = ValidatedContractsRelation.new(test_adapter)

      expect_raises(Quo::InvalidColumnError, /nonexistent.*does not exist.*validated_contracts/) do
        relation.select(validated_contracts: [:id, :nonexistent])
      end
    end

    it "validates columns from joined tables" do
      relation = ValidatedContractsRelation.new(test_adapter)
        .join(:user)

      # Valid column from joined table
      sql, _ = relation.select(validated_users: [:name, :email]).to_sql
      sql.should contain(%("validated_users"."name"))

      # Invalid column from joined table
      expect_raises(Quo::InvalidColumnError, /nonexistent.*does not exist.*validated_users/) do
        relation.select(validated_users: [:nonexistent])
      end
    end
  end

  describe "where hash validation" do
    it "allows valid columns" do
      relation = ValidatedContractsRelation.new(test_adapter)
        .where(validated_contracts: {status: "active"})

      sql, params = relation.to_sql
      sql.should contain(%("validated_contracts"."status" = $1))
      params.should eq(["active"])
    end

    it "raises error for invalid column" do
      relation = ValidatedContractsRelation.new(test_adapter)

      expect_raises(Quo::InvalidColumnError, /nonexistent.*does not exist/) do
        relation.where(validated_contracts: {nonexistent: "value"})
      end
    end
  end

  describe "where expression validation" do
    it "allows valid columns in expressions" do
      relation = ValidatedContractsRelation.new(test_adapter)
        .where { |e| e[:validated_contracts][:status] == "active" }

      sql, params = relation.to_sql
      sql.should contain(%("validated_contracts"."status" = $1))
      params.should eq(["active"])
    end

    it "raises error for invalid column in expression" do
      relation = ValidatedContractsRelation.new(test_adapter)

      expect_raises(Quo::InvalidColumnError, /nonexistent.*does not exist/) do
        relation.where { |e| e[:validated_contracts][:nonexistent] == "value" }
      end
    end

    it "validates columns in AND expressions" do
      relation = ValidatedContractsRelation.new(test_adapter)

      expect_raises(Quo::InvalidColumnError, /bad_column.*does not exist/) do
        relation.where { |e|
          (e[:validated_contracts][:status] == "active") & (e[:validated_contracts][:bad_column] == "x")
        }
      end
    end

    it "validates columns in OR expressions" do
      relation = ValidatedContractsRelation.new(test_adapter)

      expect_raises(Quo::InvalidColumnError, /bad_column.*does not exist/) do
        relation.where { |e|
          (e[:validated_contracts][:status] == "active") | (e[:validated_contracts][:bad_column] == "x")
        }
      end
    end

    it "validates columns in NOT expressions" do
      relation = ValidatedContractsRelation.new(test_adapter)

      expect_raises(Quo::InvalidColumnError, /bad_column.*does not exist/) do
        relation.where { |e| e.not(e[:validated_contracts][:bad_column] == "x") }
      end
    end

    it "validates columns in IN expressions" do
      relation = ValidatedContractsRelation.new(test_adapter)

      expect_raises(Quo::InvalidColumnError, /bad_column.*does not exist/) do
        relation.where { |e| e[:validated_contracts][:bad_column].in(["a", "b"]) }
      end
    end

    it "validates columns in BETWEEN expressions" do
      relation = ValidatedContractsRelation.new(test_adapter)

      expect_raises(Quo::InvalidColumnError, /bad_column.*does not exist/) do
        relation.where { |e| e[:validated_contracts][:bad_column].between(1, 10) }
      end
    end

    it "validates columns in LIKE expressions" do
      relation = ValidatedContractsRelation.new(test_adapter)

      expect_raises(Quo::InvalidColumnError, /bad_column.*does not exist/) do
        relation.where { |e| e[:validated_contracts][:bad_column].like("%test%") }
      end
    end

    it "validates columns in IS NULL expressions" do
      relation = ValidatedContractsRelation.new(test_adapter)

      expect_raises(Quo::InvalidColumnError, /bad_column.*does not exist/) do
        relation.where { |e| e[:validated_contracts][:bad_column].is_null }
      end
    end
  end

  describe "order validation" do
    it "allows valid columns" do
      relation = ValidatedContractsRelation.new(test_adapter)
        .order(validated_contracts: {created_at: :desc})

      sql, _ = relation.to_sql
      sql.should contain(%(ORDER BY "validated_contracts"."created_at" DESC))
    end

    it "raises error for invalid column" do
      relation = ValidatedContractsRelation.new(test_adapter)

      expect_raises(Quo::InvalidColumnError, /nonexistent.*does not exist/) do
        relation.order(validated_contracts: {nonexistent: :desc})
      end
    end
  end
end

describe "Type Checking" do
  describe "where hash type checking" do
    it "allows correct types" do
      relation = ValidatedContractsRelation.new(test_adapter)
        .where(validated_contracts: {status: "active"})       # String for String column
        .where(validated_contracts: {amount_cents: 1000_i64}) # Int64 for Int64 column
        .where(validated_contracts: {active: true})           # Bool for Bool column

      sql, params = relation.to_sql
      params.should eq(["active", 1000_i64, true])
    end

    it "raises error for type mismatch - String to Int64" do
      relation = ValidatedContractsRelation.new(test_adapter)

      expect_raises(Quo::TypeError, /Type mismatch.*amount_cents.*expected Int64.*got String/) do
        relation.where(validated_contracts: {amount_cents: "not a number"})
      end
    end

    it "raises error for type mismatch - Int to String" do
      relation = ValidatedContractsRelation.new(test_adapter)

      expect_raises(Quo::TypeError, /Type mismatch.*status.*expected String.*got Int/) do
        relation.where(validated_contracts: {status: 123})
      end
    end

    it "raises error for type mismatch - String to Bool" do
      relation = ValidatedContractsRelation.new(test_adapter)

      expect_raises(Quo::TypeError, /Type mismatch.*active.*expected Bool.*got String/) do
        relation.where(validated_contracts: {active: "yes"})
      end
    end

    it "allows Int32 for Int64 column (widening)" do
      relation = ValidatedContractsRelation.new(test_adapter)
        .where(validated_contracts: {amount_cents: 1000}) # Int32 should work for Int64

      sql, _ = relation.to_sql
      sql.should contain(%("validated_contracts"."amount_cents" = $1))
    end
  end

  describe "where expression type checking" do
    it "allows correct types in expressions" do
      relation = ValidatedContractsRelation.new(test_adapter)
        .where { |e| e[:validated_contracts][:amount_cents] >= 1000_i64 }

      sql, params = relation.to_sql
      sql.should contain(%("validated_contracts"."amount_cents" >= $1))
      params.should eq([1000_i64])
    end

    it "raises error for type mismatch in expression" do
      relation = ValidatedContractsRelation.new(test_adapter)

      expect_raises(Quo::TypeError, /Type mismatch.*amount_cents.*expected Int64.*got String/) do
        relation.where { |e| e[:validated_contracts][:amount_cents] >= "not a number" }
      end
    end

    it "type checks values in IN expressions" do
      relation = ValidatedContractsRelation.new(test_adapter)

      expect_raises(Quo::TypeError, /Type mismatch.*status.*expected String.*got Int/) do
        relation.where { |e| e[:validated_contracts][:status].in([1, 2, 3]) }
      end
    end

    it "type checks values in BETWEEN expressions" do
      relation = ValidatedContractsRelation.new(test_adapter)

      expect_raises(Quo::TypeError, /Type mismatch.*amount_cents.*expected Int64.*got String/) do
        relation.where { |e| e[:validated_contracts][:amount_cents].between("a", "z") }
      end
    end
  end
end

describe "SchemaRegistry" do
  it "registers schemas automatically" do
    Quo::SchemaRegistry.registered?(:validated_contracts).should be_true
    Quo::SchemaRegistry.registered?(:validated_users).should be_true
  end

  it "returns schema by table name" do
    schema = Quo::SchemaRegistry.get(:validated_contracts)
    schema.should_not be_nil
    schema.not_nil!.table_name.should eq(:validated_contracts)
  end

  it "returns nil for unregistered table" do
    Quo::SchemaRegistry.get(:nonexistent_table).should be_nil
  end

  it "skips validation for unregistered tables" do
    # This should not raise because :unregistered_table is not in the registry
    # The validation is skipped for flexibility (e.g., explicit joins to tables without Relations)
    relation = ValidatedContractsRelation.new(test_adapter)
      .join(:unregistered_table, on: {validated_contracts: :id, eq: {unregistered_table: :contract_id}})
      .select(unregistered_table: [:some_column]) # No error - unregistered table is not validated

    sql, _ = relation.to_sql
    sql.should contain(%("unregistered_table"."some_column"))
  end
end
