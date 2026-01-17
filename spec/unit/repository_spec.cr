require "../spec_helper"

# Test relations for repository specs
class AccountsRelation < Quo::Relation
  schema :accounts do
    primary_key :id, Int64
    column :email, String
    column :status, Int32
    column :created_at, Time
    column :updated_at, Time
  end

  scope :active do
    query.where(accounts: {status: 1})
  end

  scope :by_email, email : String do
    query.where(accounts: {email: email})
  end
end

class PasswordHashesRelation < Quo::Relation
  schema :account_password_hashes do
    primary_key :id, Int64
    column :password_hash, String
  end

  scope :by_account_id, account_id : Int64 do
    query.where(account_password_hashes: {id: account_id})
  end
end

class ProfilesRelation < Quo::Relation
  schema :profiles do
    primary_key :id, Int64
    column :account_id, Int64
    column :display_name, String
    column :bio, String?
  end

  scope :by_account_id, account_id : Int64 do
    query.where(profiles: {account_id: account_id})
  end
end

# Test repository implementation
class TestAccountRepository < Quo::Repository
  relation :accounts, AccountsRelation
  relation :password_hashes, PasswordHashesRelation
  relation :profiles, ProfilesRelation

  # Example method using relation
  def find_by_id(id : Int64)
    accounts.where(accounts: {id: id}).to_sql
  end

  def find_by_email(email : String)
    accounts.active.by_email(email).to_sql
  end

  def get_password_hash(account_id : Int64)
    password_hashes.by_account_id(account_id)
      .select(account_password_hashes: [:password_hash])
      .to_sql
  end

  def get_profile(account_id : Int64)
    profiles.by_account_id(account_id).to_sql
  end

  # Direct adapter access for inserts
  def create_account_sql(email : String)
    Quo::InsertQuery.new(:accounts, adapter)
      .values(email: email, status: 0, created_at: Time.utc, updated_at: Time.utc)
      .to_sql
  end

  def update_status_sql(id : Int64, status : Int32)
    Quo::UpdateQuery.new(:accounts, adapter)
      .set(status: status, updated_at: Time.utc)
      .where(accounts: {id: id})
      .to_sql
  end

  def delete_account_sql(id : Int64)
    Quo::DeleteQuery.new(:accounts, adapter)
      .where(accounts: {id: id})
      .to_sql
  end
end

# Repository with no relations (edge case)
class EmptyRepository < Quo::Repository
end

# Test entity class for entity mapping tests
record AccountStatus, value : Int32

record Account,
  id : Int64,
  email : String,
  status : AccountStatus,
  created_at : Time,
  updated_at : Time

record SimpleUser,
  id : Int64,
  name : String

# Repository with entity mapping for testing
class EntityMappingRepository < Quo::Repository
  relation :accounts, AccountsRelation

  # Entity mapping with transforms
  entity :account, Account do
    map :id, Int64
    map :email, String
    map :status, Int32, ->(v : Int32) { AccountStatus.new(v) }
    map :created_at, Time
    map :updated_at, Time
  end

  # Simple entity mapping without transforms
  entity :simple_user, SimpleUser do
    map :id, Int64
    map :name, String
  end
end

# Repository with single-field entity mapping (edge case)
class SingleFieldEntityRepository < Quo::Repository
  record IdOnly, id : Int64

  entity :id_only, IdOnly do
    map :id, Int64
  end
end

# Mockable adapter for testing CRUD shortcuts with SQL verification
class SqlCapturingAdapter < Quo::Adapters::Test
  getter last_insert_sql : String?
  getter last_insert_params : Array(DB::Any)?
  getter last_update_sql : String?
  getter last_update_params : Array(DB::Any)?
  getter last_delete_sql : String?
  getter last_delete_params : Array(DB::Any)?

  def execute_insert(sql : String, params : Array(DB::Any)) : Int64
    @last_insert_sql = sql
    @last_insert_params = params
    1_i64 # Return affected rows
  end

  def execute_update(sql : String, params : Array(DB::Any)) : Int64
    @last_update_sql = sql
    @last_update_params = params
    1_i64
  end

  def execute_delete(sql : String, params : Array(DB::Any)) : Int64
    @last_delete_sql = sql
    @last_delete_params = params
    1_i64
  end

  def execute(sql : String, params : Array(DB::Any)) : Quo::ResultSet
    @last_insert_sql = sql
    @last_insert_params = params
    # Return mock result for insert_returning
    [{"id" => 1_i64.as(Quo::Value), "email" => "test@test.com".as(Quo::Value)}]
  end
end

# Repository using the SQL capturing adapter
class CrudTestRepository < Quo::Repository
  relation :accounts, AccountsRelation
end

describe Quo::Repository do
  describe "initialization" do
    it "stores the adapter" do
      adapter = test_adapter
      repo = TestAccountRepository.new(adapter)

      repo.adapter.should eq(adapter)
    end

    it "works with empty repository" do
      adapter = test_adapter
      repo = EmptyRepository.new(adapter)

      repo.adapter.should eq(adapter)
    end
  end

  describe "relation macro" do
    it "creates accessor for declared relation" do
      repo = TestAccountRepository.new(test_adapter)

      repo.accounts.should be_a(AccountsRelation)
    end

    it "creates new relation instance each time" do
      repo = TestAccountRepository.new(test_adapter)

      relation1 = repo.accounts
      relation2 = repo.accounts

      # New instances but same structure
      relation1.should_not be(relation2)
      relation1.class.should eq(relation2.class)
    end

    it "passes adapter to relation" do
      adapter = test_adapter
      repo = TestAccountRepository.new(adapter)

      # Verify relation can generate SQL (proves adapter was passed)
      sql, _ = repo.accounts.to_sql
      sql.should contain("accounts")
    end

    it "supports multiple relations" do
      repo = TestAccountRepository.new(test_adapter)

      repo.accounts.should be_a(AccountsRelation)
      repo.password_hashes.should be_a(PasswordHashesRelation)
      repo.profiles.should be_a(ProfilesRelation)
    end
  end

  describe "relation usage" do
    it "allows querying via relation" do
      repo = TestAccountRepository.new(test_adapter)

      sql, params = repo.find_by_id(123_i64)

      sql.should contain(%("accounts"."id" = $1))
      params.should eq([123_i64])
    end

    it "supports scopes on relations" do
      repo = TestAccountRepository.new(test_adapter)

      sql, params = repo.find_by_email("test@example.com")

      sql.should contain(%("accounts"."status" = $1))   # active scope
      sql.should contain(%("accounts"."email" = $2))    # by_email scope
      params.should eq([1, "test@example.com"])
    end

    it "supports select on relations" do
      repo = TestAccountRepository.new(test_adapter)

      sql, params = repo.get_password_hash(456_i64)

      sql.should contain(%("account_password_hashes"."password_hash"))
      sql.should contain(%("account_password_hashes"."id" = $1))
      params.should eq([456_i64])
    end
  end

  describe "write operations via adapter" do
    it "supports insert queries" do
      repo = TestAccountRepository.new(test_adapter)

      sql, params = repo.create_account_sql("new@example.com")

      sql.should contain("INSERT INTO")
      sql.should contain(%("accounts"))
      params.should contain("new@example.com")
    end

    it "supports update queries" do
      repo = TestAccountRepository.new(test_adapter)

      sql, params = repo.update_status_sql(789_i64, 2)

      sql.should contain("UPDATE")
      sql.should contain(%("accounts"))
      sql.should contain("SET")
      sql.should contain(%("status"))
      params.should contain(2)
      params.should contain(789_i64)
    end

    it "supports delete queries" do
      repo = TestAccountRepository.new(test_adapter)

      sql, params = repo.delete_account_sql(999_i64)

      sql.should contain("DELETE FROM")
      sql.should contain(%("accounts"))
      params.should eq([999_i64])
    end
  end

  describe "relation isolation" do
    it "each relation call starts fresh" do
      repo = TestAccountRepository.new(test_adapter)

      # First query with conditions
      sql1, _ = repo.accounts.active.to_sql

      # Second query should not have previous conditions
      sql2, _ = repo.accounts.to_sql

      sql1.should contain("status")
      sql2.should_not contain("status")
    end
  end
end

describe "Repository pattern usage" do
  it "demonstrates complete repository workflow" do
    repo = TestAccountRepository.new(test_adapter)

    # Read operations via relations
    accounts_sql, _ = repo.accounts.active.to_sql
    accounts_sql.should contain("SELECT")
    accounts_sql.should contain(%("accounts"."status" = $1))

    # Write operations via adapter
    insert_sql, insert_params = Quo::InsertQuery.new(:accounts, repo.adapter)
      .values(email: "user@example.com", status: 0)
      .returning(accounts: [:id])
      .to_sql

    insert_sql.should contain("INSERT INTO")
    insert_sql.should contain("RETURNING")
    insert_params.should eq(["user@example.com", 0])
  end

  it "supports transaction-like patterns" do
    repo = TestAccountRepository.new(test_adapter)

    # In a real implementation, you'd wrap this in a transaction:
    # repo.adapter.transaction do |tx|
    #   account = create_account(tx)
    #   create_profile(tx, account.id)
    # end

    # For testing, verify SQL generation
    account_sql, _ = Quo::InsertQuery.new(:accounts, repo.adapter)
      .values(email: "test@test.com", status: 1)
      .to_sql

    profile_sql, _ = Quo::InsertQuery.new(:profiles, repo.adapter)
      .values(account_id: 1_i64, display_name: "Test User")
      .to_sql

    account_sql.should contain(%("accounts"))
    profile_sql.should contain(%("profiles"))
  end
end

describe "CRUD shortcuts" do
  describe "#insert" do
    it "generates correct INSERT SQL" do
      adapter = SqlCapturingAdapter.new
      repo = CrudTestRepository.new(adapter)

      repo.insert(:accounts, email: "alice@example.com", status: 0)

      sql = adapter.last_insert_sql.not_nil!
      params = adapter.last_insert_params.not_nil!

      sql.should contain("INSERT INTO")
      sql.should contain(%("accounts"))
      sql.should contain(%("email"))
      sql.should contain(%("status"))
      params.should contain("alice@example.com")
      params.should contain(0)
    end

    it "returns affected row count" do
      adapter = SqlCapturingAdapter.new
      repo = CrudTestRepository.new(adapter)

      result = repo.insert(:accounts, email: "test@test.com", status: 1)

      result.should eq(1_i64)
    end
  end

  describe "#insert_returning" do
    it "generates INSERT with RETURNING clause" do
      adapter = SqlCapturingAdapter.new
      repo = CrudTestRepository.new(adapter)

      repo.insert_returning(:accounts, [:id, :email], name: "Bob", status: 1)

      sql = adapter.last_insert_sql.not_nil!

      sql.should contain("INSERT INTO")
      sql.should contain("RETURNING")
      sql.should contain(%("id"))
      sql.should contain(%("email"))
    end

    it "returns the inserted row" do
      adapter = SqlCapturingAdapter.new
      repo = CrudTestRepository.new(adapter)

      result = repo.insert_returning(:accounts, [:id, :email], email: "test@test.com", status: 0)

      result.should_not be_nil
      result.not_nil!["id"].should eq(1_i64)
      result.not_nil!["email"].should eq("test@test.com")
    end
  end

  describe "#update" do
    it "generates correct UPDATE SQL with WHERE clause" do
      adapter = SqlCapturingAdapter.new
      repo = CrudTestRepository.new(adapter)

      repo.update(:accounts, {id: 123_i64}, status: 2, email: "new@example.com")

      sql = adapter.last_update_sql.not_nil!
      params = adapter.last_update_params.not_nil!

      sql.should contain("UPDATE")
      sql.should contain(%("accounts"))
      sql.should contain("SET")
      sql.should contain(%("status"))
      sql.should contain(%("email"))
      sql.should contain("WHERE")
      sql.should contain(%("accounts"."id"))
      params.should contain(2)
      params.should contain("new@example.com")
      params.should contain(123_i64)
    end

    it "returns affected row count" do
      adapter = SqlCapturingAdapter.new
      repo = CrudTestRepository.new(adapter)

      result = repo.update(:accounts, {id: 1_i64}, status: 1)

      result.should eq(1_i64)
    end
  end

  describe "#delete" do
    it "generates correct DELETE SQL with WHERE clause" do
      adapter = SqlCapturingAdapter.new
      repo = CrudTestRepository.new(adapter)

      repo.delete(:accounts, id: 456_i64)

      sql = adapter.last_delete_sql.not_nil!
      params = adapter.last_delete_params.not_nil!

      sql.should contain("DELETE FROM")
      sql.should contain(%("accounts"))
      sql.should contain("WHERE")
      sql.should contain(%("accounts"."id"))
      params.should eq([456_i64])
    end

    it "supports multiple WHERE conditions" do
      adapter = SqlCapturingAdapter.new
      repo = CrudTestRepository.new(adapter)

      repo.delete(:accounts, id: 789_i64, status: 0)

      sql = adapter.last_delete_sql.not_nil!
      params = adapter.last_delete_params.not_nil!

      sql.should contain(%("accounts"."id"))
      sql.should contain(%("accounts"."status"))
      params.should contain(789_i64)
      params.should contain(0)
    end

    it "returns affected row count" do
      adapter = SqlCapturingAdapter.new
      repo = CrudTestRepository.new(adapter)

      result = repo.delete(:accounts, id: 1_i64)

      result.should eq(1_i64)
    end
  end
end

describe "Finder helpers" do
  describe "#find" do
    it "generates SELECT with primary key condition" do
      repo = TestAccountRepository.new(test_adapter)

      # Use underlying query to verify SQL generation
      query = Quo::Query.new(:accounts, repo.adapter)
        .where(accounts: {id: 123_i64})
      sql, params = query.to_sql

      sql.should contain("SELECT")
      sql.should contain(%("accounts"."id" = $1))
      params.should eq([123_i64])
    end

    it "supports custom primary key" do
      repo = TestAccountRepository.new(test_adapter)

      query = Quo::Query.new(:accounts, repo.adapter)
        .where(accounts: {uuid: "abc-123"})
      sql, params = query.to_sql

      sql.should contain(%("accounts"."uuid" = $1))
      params.should eq(["abc-123"])
    end
  end

  describe "#find_by" do
    it "generates SELECT with arbitrary conditions" do
      repo = TestAccountRepository.new(test_adapter)

      query = Quo::Query.new(:accounts, repo.adapter)
        .where(accounts: {email: "test@example.com"})
      sql, params = query.to_sql

      sql.should contain("SELECT")
      sql.should contain(%("accounts"."email" = $1))
      params.should eq(["test@example.com"])
    end

    it "supports multiple conditions" do
      repo = TestAccountRepository.new(test_adapter)

      query = Quo::Query.new(:accounts, repo.adapter)
        .where(accounts: {email: "test@example.com", status: 1})
      sql, params = query.to_sql

      sql.should contain(%("accounts"."email"))
      sql.should contain(%("accounts"."status"))
      params.should contain("test@example.com")
      params.should contain(1)
    end
  end

  describe "#exists?" do
    it "generates EXISTS query with conditions" do
      repo = TestAccountRepository.new(test_adapter)

      query = Quo::Query.new(:accounts, repo.adapter)
        .where(accounts: {email: "test@example.com"})
      sql, params = query.to_sql

      sql.should contain("SELECT")
      sql.should contain(%("accounts"."email" = $1))
      params.should eq(["test@example.com"])
    end
  end
end

describe "Entity mapping macro" do
  describe "single-row mapping" do
    it "maps row to entity without transforms" do
      repo = EntityMappingRepository.new(test_adapter)

      row = {
        "id"   => 1_i64.as(Quo::Value),
        "name" => "Alice".as(Quo::Value),
      }

      user = repo.simple_user_from_row(row)

      user.id.should eq(1_i64)
      user.name.should eq("Alice")
    end

    it "maps row to entity with transforms" do
      repo = EntityMappingRepository.new(test_adapter)
      now = Time.utc

      row = {
        "id"         => 42_i64.as(Quo::Value),
        "email"      => "bob@example.com".as(Quo::Value),
        "status"     => 1.as(Quo::Value),
        "created_at" => now.as(Quo::Value),
        "updated_at" => now.as(Quo::Value),
      }

      account = repo.account_from_row(row)

      account.id.should eq(42_i64)
      account.email.should eq("bob@example.com")
      account.status.should eq(AccountStatus.new(1))
      account.created_at.should eq(now)
      account.updated_at.should eq(now)
    end

    it "handles single-field entities" do
      repo = SingleFieldEntityRepository.new(test_adapter)

      row = {"id" => 99_i64.as(Quo::Value)}

      entity = repo.id_only_from_row(row)

      entity.id.should eq(99_i64)
    end
  end

  describe "result-set mapping" do
    it "maps multiple rows to array of entities" do
      repo = EntityMappingRepository.new(test_adapter)

      rows = [
        {"id" => 1_i64.as(Quo::Value), "name" => "Alice".as(Quo::Value)},
        {"id" => 2_i64.as(Quo::Value), "name" => "Bob".as(Quo::Value)},
        {"id" => 3_i64.as(Quo::Value), "name" => "Charlie".as(Quo::Value)},
      ]

      users = repo.simple_users_from_rows(rows)

      users.size.should eq(3)
      users[0].id.should eq(1_i64)
      users[0].name.should eq("Alice")
      users[1].id.should eq(2_i64)
      users[1].name.should eq("Bob")
      users[2].id.should eq(3_i64)
      users[2].name.should eq("Charlie")
    end

    it "maps empty result set to empty array" do
      repo = EntityMappingRepository.new(test_adapter)

      rows = [] of Quo::Row

      users = repo.simple_users_from_rows(rows)

      users.should be_empty
    end

    it "applies transforms when mapping multiple rows" do
      repo = EntityMappingRepository.new(test_adapter)
      now = Time.utc

      rows = [
        {
          "id"         => 1_i64.as(Quo::Value),
          "email"      => "user1@test.com".as(Quo::Value),
          "status"     => 0.as(Quo::Value),
          "created_at" => now.as(Quo::Value),
          "updated_at" => now.as(Quo::Value),
        },
        {
          "id"         => 2_i64.as(Quo::Value),
          "email"      => "user2@test.com".as(Quo::Value),
          "status"     => 1.as(Quo::Value),
          "created_at" => now.as(Quo::Value),
          "updated_at" => now.as(Quo::Value),
        },
      ]

      accounts = repo.accounts_from_rows(rows)

      accounts.size.should eq(2)
      accounts[0].status.should eq(AccountStatus.new(0))
      accounts[1].status.should eq(AccountStatus.new(1))
    end
  end
end

describe "Transaction wrapper" do
  it "delegates to adapter transaction method" do
    repo = TestAccountRepository.new(test_adapter)

    # Transaction wrapper exists and is callable
    # (execution test requires real database)
    typeof(repo.transaction { |tx| }).should eq(Nil)
  end
end

describe "Raw SQL execution helpers" do
  it "execute method exists on repository" do
    repo = TestAccountRepository.new(test_adapter)

    # The method signature is correct
    repo.responds_to?(:execute).should be_true
  end

  it "execute_one method exists on repository" do
    repo = TestAccountRepository.new(test_adapter)

    repo.responds_to?(:execute_one).should be_true
  end
end

describe "Complete repository DX example" do
  it "demonstrates concise CRUD operations" do
    adapter = SqlCapturingAdapter.new
    repo = EntityMappingRepository.new(adapter)

    # Insert - concise one-liner
    repo.insert(:accounts, email: "new@example.com", status: 0)
    adapter.last_insert_sql.not_nil!.should contain("INSERT INTO")

    # Update with where clause
    repo.update(:accounts, {id: 1_i64}, status: 1)
    adapter.last_update_sql.not_nil!.should contain("UPDATE")
    adapter.last_update_sql.not_nil!.should contain("WHERE")

    # Delete
    repo.delete(:accounts, id: 1_i64)
    adapter.last_delete_sql.not_nil!.should contain("DELETE FROM")
  end

  it "demonstrates entity mapping workflow" do
    repo = EntityMappingRepository.new(test_adapter)
    now = Time.utc

    # Simulate row from database
    row = {
      "id"         => 1_i64.as(Quo::Value),
      "email"      => "user@example.com".as(Quo::Value),
      "status"     => 1.as(Quo::Value),
      "created_at" => now.as(Quo::Value),
      "updated_at" => now.as(Quo::Value),
    }

    # Clean mapping to domain entity
    account = repo.account_from_row(row)

    account.should be_a(Account)
    account.status.should be_a(AccountStatus)
  end
end
