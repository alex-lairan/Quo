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
