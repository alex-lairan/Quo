require "../spec_helper"

include Quo::ColumnHelpers

# Test relation for specs
class TestContractsRelation < Quo::Relation
  schema :contracts do
    primary_key :id, String
    column :reference, String
    column :status, String
    column :amount_cents, Int64
    column :user_id, String
    column :created_at, Time
  end

  scope :active do
    query.where(contracts: {status: "active"})
  end

  scope :for_user, user_id : String do
    query.where(contracts: {user_id: user_id})
  end

  scope :high_value, min_cents : Int64 do
    query.where { |e| e[:contracts][:amount_cents] >= min_cents }
  end

  scope :by_recent do
    query.order(contracts: {created_at: :desc})
  end

  scope :with_ref_alias do
    query.select(t(:contracts)[:reference].aliased(:ref))
  end
end

# Another test relation for association testing
class TestUsersRelation < Quo::Relation
  schema :users do
    primary_key :id, String
    column :name, String
    column :email, String
  end
end

describe Quo::Relation do
  describe "schema definition" do
    it "defines table name" do
      TestContractsRelation.table_name.should eq(:contracts)
    end

    it "defines columns" do
      schema = TestContractsRelation.schema_definition
      schema.has_column?(:id).should be_true
      schema.has_column?(:reference).should be_true
      schema.has_column?(:status).should be_true
      schema.has_column?(:amount_cents).should be_true
    end

    it "defines primary key" do
      schema = TestContractsRelation.schema_definition
      schema.primary_key.should eq(:id)
    end

    it "stores column types" do
      schema = TestContractsRelation.schema_definition
      schema.column(:status).not_nil!.type_name.should eq("String")
      schema.column(:amount_cents).not_nil!.type_name.should eq("Int64")
    end
  end

  describe "scopes" do
    it "creates scope method without arguments" do
      relation = TestContractsRelation.new(test_adapter)
      scoped = relation.active

      sql, params = scoped.to_sql
      sql.should contain(%("contracts"."status" = $1))
      params.should eq(["active"])
    end

    it "chains scopes" do
      relation = TestContractsRelation.new(test_adapter)
      scoped = relation.active.by_recent

      sql, _ = scoped.to_sql
      sql.should contain(%(WHERE))
      sql.should contain(%(ORDER BY))
    end

    it "passes arguments to scopes" do
      relation = TestContractsRelation.new(test_adapter)
      scoped = relation.for_user("user-123")

      sql, params = scoped.to_sql
      sql.should contain(%("contracts"."user_id" = $1))
      params.should eq(["user-123"])
    end

    it "supports expression block in scopes" do
      relation = TestContractsRelation.new(test_adapter)
      scoped = relation.high_value(100_000_i64)

      sql, params = scoped.to_sql
      sql.should contain(%("contracts"."amount_cents" >= $1))
      params.should eq([100_000_i64])
    end

    it "scopes are composable" do
      relation = TestContractsRelation.new(test_adapter)
      scoped = relation
        .active
        .for_user("user-123")
        .high_value(100_000_i64)
        .by_recent

      sql, params = scoped.to_sql
      sql.should contain(%("contracts"."status" = $1))
      sql.should contain(%("contracts"."user_id" = $2))
      sql.should contain(%("contracts"."amount_cents" >= $3))
      sql.should contain(%(ORDER BY "contracts"."created_at" DESC))
      params.size.should eq(3)
    end

    it "scopes do not mutate original relation" do
      relation = TestContractsRelation.new(test_adapter)
      relation.active

      sql, _ = relation.to_sql
      sql.should_not contain(%(WHERE))
    end

    it "scopes can use t() helper for aliased columns" do
      relation = TestContractsRelation.new(test_adapter)
      scoped = relation.with_ref_alias

      sql, _ = scoped.to_sql
      sql.should contain(%("contracts"."reference" AS "ref"))
    end
  end

  describe "query methods" do
    it "delegates select" do
      relation = TestContractsRelation.new(test_adapter)
        .select(contracts: [:id, :reference])

      sql, _ = relation.to_sql
      sql.should contain(%("contracts"."id"))
      sql.should contain(%("contracts"."reference"))
    end

    it "delegates where with hash" do
      relation = TestContractsRelation.new(test_adapter)
        .where(contracts: {status: "pending"})

      sql, params = relation.to_sql
      sql.should contain(%("contracts"."status" = $1))
      params.should eq(["pending"])
    end

    it "delegates where with block" do
      relation = TestContractsRelation.new(test_adapter)
        .where { |e| e[:contracts][:amount_cents] > 50000 }

      sql, params = relation.to_sql
      sql.should contain(%("contracts"."amount_cents" > $1))
      params.should eq([50000])
    end

    it "delegates join" do
      relation = TestContractsRelation.new(test_adapter)
        .join(:users, on: {contracts: :user_id, eq: {users: :id}})

      sql, _ = relation.to_sql
      sql.should contain(%(INNER JOIN "users"))
    end

    it "delegates order" do
      relation = TestContractsRelation.new(test_adapter)
        .order(contracts: {reference: :asc})

      sql, _ = relation.to_sql
      sql.should contain(%(ORDER BY "contracts"."reference" ASC))
    end

    it "delegates limit" do
      relation = TestContractsRelation.new(test_adapter)
        .limit(10)

      sql, params = relation.to_sql
      sql.should contain(%(LIMIT $1))
      params.should eq([10])
    end

    it "delegates offset" do
      relation = TestContractsRelation.new(test_adapter)
        .offset(20)

      sql, params = relation.to_sql
      sql.should contain(%(OFFSET $1))
      params.should eq([20])
    end

    it "delegates distinct" do
      relation = TestContractsRelation.new(test_adapter)
        .distinct

      sql, _ = relation.to_sql
      sql.should start_with(%(SELECT DISTINCT))
    end

    it "allows selecting columns with aliases using t() helper" do
      relation = TestContractsRelation.new(test_adapter)
        .select(t(:contracts)[:reference].aliased(:ref))

      sql, _ = relation.to_sql
      sql.should contain(%("contracts"."reference" AS "ref"))
    end

    it "allows mixing regular and aliased columns with t() helper" do
      relation = TestContractsRelation.new(test_adapter)
        .select(
          t(:contracts)[:id],
          t(:contracts)[:reference].aliased(:ref),
          t(:contracts)[:status].aliased(:state)
        )

      sql, _ = relation.to_sql
      sql.should contain(%("contracts"."id"))
      sql.should contain(%("contracts"."reference" AS "ref"))
      sql.should contain(%("contracts"."status" AS "state"))
    end

    it "allows aliasing columns from joined tables using t() helper" do
      relation = TestContractsRelation.new(test_adapter)
        .join(:users, on: {contracts: :user_id, eq: {users: :id}})
        .select(
          t(:contracts)[:reference].aliased(:contract_ref),
          t(:users)[:name].aliased(:user_name)
        )

      sql, _ = relation.to_sql
      sql.should contain(%("contracts"."reference" AS "contract_ref"))
      sql.should contain(%("users"."name" AS "user_name"))
    end

    it "can combine hash-based select with aliased columns using t() helper" do
      relation = TestContractsRelation.new(test_adapter)
        .select(contracts: [:id])
        .select(t(:contracts)[:reference].aliased(:ref))

      sql, _ = relation.to_sql
      sql.should contain(%("contracts"."id"))
      sql.should contain(%("contracts"."reference" AS "ref"))
    end
  end

  describe "immutability" do
    it "returns new relation on each method call" do
      original = TestContractsRelation.new(test_adapter)
      with_where = original.active

      original.object_id.should_not eq(with_where.object_id)
    end

    it "allows branching from same base relation" do
      base = TestContractsRelation.new(test_adapter).active

      page1 = base.limit(20).offset(0)
      page2 = base.limit(20).offset(20)

      _, params1 = page1.to_sql
      _, params2 = page2.to_sql

      params1.should eq(["active", 20, 0])
      params2.should eq(["active", 20, 20])
    end
  end
end

describe Quo::Schema do
  describe ".build" do
    it "creates schema with DSL" do
      schema = Quo::Schema.build(:test_table) do
        primary_key :id, Int64
        column :name, String
        column :active, Bool, nullable: true
      end

      schema.table_name.should eq(:test_table)
      schema.primary_key.should eq(:id)
      schema.has_column?(:id).should be_true
      schema.has_column?(:name).should be_true
      schema.has_column?(:active).should be_true
    end

    it "stores column metadata" do
      schema = Quo::Schema.build(:test_table) do
        primary_key :id, Int64
        column :name, String, nullable: true
      end

      id_col = schema.column(:id).not_nil!
      id_col.primary_key?.should be_true
      id_col.nullable?.should be_false

      name_col = schema.column(:name).not_nil!
      name_col.primary_key?.should be_false
      name_col.nullable?.should be_true
    end
  end

  describe "#column_names" do
    it "returns all column names" do
      schema = Quo::Schema.build(:test_table) do
        primary_key :id, Int64
        column :name, String
        column :email, String
      end

      names = schema.column_names
      names.should contain(:id)
      names.should contain(:name)
      names.should contain(:email)
    end
  end
end
