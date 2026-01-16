require "sqlite3"
require "../src/quo"

# =============================================================================
# DEMO SQLITE - Quo Query Builder avec SQLite
# =============================================================================
#
# Cette demo montre l'utilisation de Quo avec une vraie base SQLite.
# Elle crée une DB en mémoire, insère des données, et exécute des queries.
#
# Usage: crystal run examples/demo_sqlite.cr
#

# =============================================================================
# SCHEMA DEFINITIONS
# =============================================================================

class UsersRelation < Quo::Relation
  schema :users do
    primary_key :id, Int64
    column :email, String
    column :name, String
    column :role, String
    column :active, Bool
    column :created_at, String  # SQLite stores dates as TEXT
  end

  scope :active do
    query.where(users: {active: true})
  end

  scope :admins do
    query.where(users: {role: "admin"})
  end

  scope :by_role, role : String do
    query.where(users: {role: role})
  end
end

class CompaniesRelation < Quo::Relation
  schema :companies do
    primary_key :id, Int64
    column :name, String
    column :country, String
    column :active, Bool
  end

  scope :active do
    query.where(companies: {active: true})
  end

  scope :in_country, country : String do
    query.where(companies: {country: country})
  end
end

class ContractsRelation < Quo::Relation
  schema :contracts do
    primary_key :id, Int64
    column :reference, String
    column :user_id, Int64
    column :company_id, Int64
    column :status, String
    column :amount_cents, Int64
    column :created_at, String

    belongs_to :user, :user_id, :users
    belongs_to :company, :company_id, :companies
  end

  scope :active do
    query.where(contracts: {status: "active"})
  end

  scope :pending do
    query.where(contracts: {status: "pending"})
  end

  scope :high_value, min : Int64 do
    query.where { |e| e[:contracts][:amount_cents] >= min }
  end
end

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

def print_section(title : String)
  puts "\n" + "=" * 80
  puts "  #{title}"
  puts "=" * 80
end

def print_query(name : String, sql : String, params : Array(DB::Any))
  puts "\n#{name}"
  puts "-" * 60
  puts "SQL: #{sql}"
  puts "Params: #{params.inspect}"
end

def print_results(results : Array(Hash(String, DB::Any)))
  if results.empty?
    puts "  (no results)"
  else
    results.each_with_index do |row, i|
      puts "  [#{i + 1}] #{row}"
    end
  end
end

# =============================================================================
# MAIN DEMO
# =============================================================================

puts "\n" + "=" * 80
puts "  QUO - SQLite Demo"
puts "  Demonstration avec une vraie base SQLite en memoire"
puts "=" * 80

# Creer une base SQLite en memoire
DB.open "sqlite3::memory:" do |db|
  adapter = Quo::Adapters::SQLite.new(db)

  # ---------------------------------------------------------------------------
  # CREATION DES TABLES
  # ---------------------------------------------------------------------------
  print_section("1. Creation des tables")

  db.exec <<-SQL
    CREATE TABLE users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      email TEXT NOT NULL,
      name TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'user',
      active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP
    )
  SQL
  puts "  Table 'users' creee"

  db.exec <<-SQL
    CREATE TABLE companies (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      country TEXT NOT NULL,
      active INTEGER NOT NULL DEFAULT 1
    )
  SQL
  puts "  Table 'companies' creee"

  db.exec <<-SQL
    CREATE TABLE contracts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      reference TEXT NOT NULL,
      user_id INTEGER NOT NULL,
      company_id INTEGER NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      amount_cents INTEGER NOT NULL,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (user_id) REFERENCES users(id),
      FOREIGN KEY (company_id) REFERENCES companies(id)
    )
  SQL
  puts "  Table 'contracts' creee"

  # ---------------------------------------------------------------------------
  # INSERTION DES DONNEES
  # ---------------------------------------------------------------------------
  print_section("2. Insertion des donnees")

  # Users
  db.exec "INSERT INTO users (email, name, role, active) VALUES (?, ?, ?, ?)",
    "alice@example.com", "Alice Martin", "admin", 1
  db.exec "INSERT INTO users (email, name, role, active) VALUES (?, ?, ?, ?)",
    "bob@example.com", "Bob Dupont", "manager", 1
  db.exec "INSERT INTO users (email, name, role, active) VALUES (?, ?, ?, ?)",
    "charlie@example.com", "Charlie Durand", "user", 1
  db.exec "INSERT INTO users (email, name, role, active) VALUES (?, ?, ?, ?)",
    "david@example.com", "David Inactive", "user", 0
  puts "  4 users inseres"

  # Companies
  db.exec "INSERT INTO companies (name, country, active) VALUES (?, ?, ?)",
    "TechCorp France", "France", 1
  db.exec "INSERT INTO companies (name, country, active) VALUES (?, ?, ?)",
    "DataSoft Belgium", "Belgium", 1
  db.exec "INSERT INTO companies (name, country, active) VALUES (?, ?, ?)",
    "OldCo Inactive", "France", 0
  puts "  3 companies inserees"

  # Contracts
  db.exec "INSERT INTO contracts (reference, user_id, company_id, status, amount_cents) VALUES (?, ?, ?, ?, ?)",
    "CTR-001", 1, 1, "active", 50000_i64
  db.exec "INSERT INTO contracts (reference, user_id, company_id, status, amount_cents) VALUES (?, ?, ?, ?, ?)",
    "CTR-002", 1, 2, "active", 75000_i64
  db.exec "INSERT INTO contracts (reference, user_id, company_id, status, amount_cents) VALUES (?, ?, ?, ?, ?)",
    "CTR-003", 2, 1, "pending", 30000_i64
  db.exec "INSERT INTO contracts (reference, user_id, company_id, status, amount_cents) VALUES (?, ?, ?, ?, ?)",
    "CTR-004", 3, 2, "cancelled", 10000_i64
  db.exec "INSERT INTO contracts (reference, user_id, company_id, status, amount_cents) VALUES (?, ?, ?, ?, ?)",
    "CTR-005", 2, 1, "active", 120000_i64
  puts "  5 contracts inseres"

  # ---------------------------------------------------------------------------
  # QUERIES SIMPLES
  # ---------------------------------------------------------------------------
  print_section("3. Queries simples")

  # 3.1 - Tous les users actifs
  puts "\n3.1 Tous les users actifs:"
  sql, params = UsersRelation.new(adapter)
    .select(users: [:id, :name, :email, :role])
    .active
    .to_sql
  print_query("UsersRelation.active", sql, params)
  results = adapter.execute(sql, params)
  print_results(results)

  # 3.2 - Users admin
  puts "\n3.2 Users admin:"
  sql, params = UsersRelation.new(adapter)
    .select(users: [:id, :name, :role])
    .admins
    .to_sql
  print_query("UsersRelation.admins", sql, params)
  results = adapter.execute(sql, params)
  print_results(results)

  # 3.3 - Companies en France
  puts "\n3.3 Companies en France:"
  sql, params = CompaniesRelation.new(adapter)
    .select(companies: [:id, :name, :country])
    .in_country("France")
    .to_sql
  print_query("CompaniesRelation.in_country('France')", sql, params)
  results = adapter.execute(sql, params)
  print_results(results)

  # ---------------------------------------------------------------------------
  # QUERIES AVEC EXPRESSIONS
  # ---------------------------------------------------------------------------
  print_section("4. Queries avec expressions")

  # 4.1 - Contracts avec montant >= 50000
  puts "\n4.1 Contracts high value (>= 500 EUR):"
  sql, params = ContractsRelation.new(adapter)
    .select(contracts: [:id, :reference, :amount_cents, :status])
    .high_value(50000_i64)
    .to_sql
  print_query("ContractsRelation.high_value(50000)", sql, params)
  results = adapter.execute(sql, params)
  print_results(results)

  # 4.2 - Contracts actifs OU pending
  puts "\n4.2 Contracts actifs OU pending:"
  sql, params = ContractsRelation.new(adapter)
    .select(contracts: [:id, :reference, :status])
    .where { |e|
      (e[:contracts][:status] == "active") | (e[:contracts][:status] == "pending")
    }
    .to_sql
  print_query("where status = 'active' OR status = 'pending'", sql, params)
  results = adapter.execute(sql, params)
  print_results(results)

  # 4.3 - Contracts avec montant entre 20000 et 80000
  puts "\n4.3 Contracts avec montant entre 200 et 800 EUR:"
  sql, params = ContractsRelation.new(adapter)
    .select(contracts: [:id, :reference, :amount_cents])
    .where { |e| e[:contracts][:amount_cents].between(20000_i64, 80000_i64) }
    .to_sql
  print_query("where amount_cents BETWEEN 20000 AND 80000", sql, params)
  results = adapter.execute(sql, params)
  print_results(results)

  # 4.4 - Contracts avec status IN (...)
  puts "\n4.4 Contracts avec status IN ('active', 'pending'):"
  sql, params = ContractsRelation.new(adapter)
    .select(contracts: [:id, :reference, :status])
    .where { |e| e[:contracts][:status].in(["active", "pending"]) }
    .to_sql
  print_query("where status IN ('active', 'pending')", sql, params)
  results = adapter.execute(sql, params)
  print_results(results)

  # ---------------------------------------------------------------------------
  # QUERIES AVEC JOINS (via associations)
  # ---------------------------------------------------------------------------
  print_section("5. Queries avec JOINs (associations)")

  # 5.1 - Contracts avec user (INNER JOIN)
  puts "\n5.1 Contracts avec info user:"
  sql, params = ContractsRelation.new(adapter)
    .select(contracts: [:id, :reference, :status], users: [:name, :email])
    .join(:user)  # Utilise l'association belongs_to
    .active
    .to_sql
  print_query("ContractsRelation.join(:user).active", sql, params)
  results = adapter.execute(sql, params)
  print_results(results)

  # 5.2 - Contracts avec user ET company
  puts "\n5.2 Contracts avec user ET company:"
  sql, params = ContractsRelation.new(adapter)
    .select(
      contracts: [:reference, :amount_cents],
      users: [:name],
      companies: [:name, :country]
    )
    .join(:user)
    .join(:company)
    .to_sql
  print_query("ContractsRelation.join(:user).join(:company)", sql, params)
  results = adapter.execute(sql, params)
  print_results(results)

  # 5.3 - Contracts avec LEFT JOIN
  puts "\n5.3 Tous les contracts (LEFT JOIN user):"
  sql, params = ContractsRelation.new(adapter)
    .select(contracts: [:id, :reference], users: [:name])
    .left_join(:user)
    .to_sql
  print_query("ContractsRelation.left_join(:user)", sql, params)
  results = adapter.execute(sql, params)
  print_results(results)

  # ---------------------------------------------------------------------------
  # QUERIES COMPLEXES
  # ---------------------------------------------------------------------------
  print_section("6. Queries complexes")

  # 6.1 - Dashboard: contracts actifs high value avec user et company
  puts "\n6.1 Dashboard - Contracts actifs high value:"
  sql, params = ContractsRelation.new(adapter)
    .select(
      contracts: [:reference, :status, :amount_cents],
      users: [:name, :role],
      companies: [:name, :country]
    )
    .join(:user)
    .join(:company)
    .active
    .high_value(50000_i64)
    .where(users: {active: true})
    .where(companies: {active: true})
    .order(contracts: {amount_cents: :desc})
    .limit(10)
    .to_sql

  print_query("Complex dashboard query", sql, params)
  results = adapter.execute(sql, params)
  print_results(results)

  # 6.2 - Count des contracts actifs
  puts "\n6.2 Count des contracts actifs:"
  sql, params = ContractsRelation.new(adapter)
    .active
    .count_sql
  print_query("ContractsRelation.active.count_sql", sql, params)
  count = db.query_one(sql, args: params, as: Int64)
  puts "  Count: #{count}"

  # 6.3 - ILIKE (case-insensitive search)
  puts "\n6.3 Recherche case-insensitive (ILIKE -> LOWER):"
  sql, params = UsersRelation.new(adapter)
    .select(users: [:id, :name, :email])
    .where { |e| e[:users][:name].ilike("%martin%") }
    .to_sql
  print_query("where name ILIKE '%martin%'", sql, params)
  results = adapter.execute(sql, params)
  print_results(results)

  # ---------------------------------------------------------------------------
  # DIFFERENCES SQLITE VS POSTGRES
  # ---------------------------------------------------------------------------
  print_section("7. Differences SQLite vs Postgres")

  puts <<-INFO

  SQLite Adapter specifics:

  1. Placeholders: ? (vs $1, $2 pour Postgres)
     Exemple: WHERE status = ? AND amount > ?

  2. ILIKE: Converti en LOWER(col) LIKE LOWER(?)
     SQLite n'a pas ILIKE nativement

  3. RIGHT JOIN / FULL JOIN: Non supportes
     SQLite ne supporte pas ces types de JOIN
     -> Utiliser LEFT JOIN avec tables inversees

  4. Types: SQLite est plus flexible
     - Booleans stockes comme INTEGER (0/1)
     - Dates stockees comme TEXT

  5. Meme SQL quote style: "table"."column"

  INFO

  # ---------------------------------------------------------------------------
  # VALIDATION DEMO
  # ---------------------------------------------------------------------------
  print_section("8. Validation (SQLite)")

  puts "\n8.1 Erreur colonne inexistante:"
  begin
    UsersRelation.new(adapter)
      .select(users: [:id, :nonexistent])
      .to_sql
  rescue ex : Quo::InvalidColumnError
    puts "  Erreur capturee: #{ex.message}"
  end

  puts "\n8.2 Erreur type mismatch:"
  begin
    ContractsRelation.new(adapter)
      .where(contracts: {amount_cents: "not a number"})
      .to_sql
  rescue ex : Quo::TypeError
    puts "  Erreur capturee: #{ex.message}"
  end

  puts "\n8.3 Erreur RIGHT JOIN non supporte:"
  begin
    ContractsRelation.new(adapter)
      .right_join(:user)
      .to_sql
  rescue ex : Quo::AdapterError
    puts "  Erreur capturee: #{ex.message}"
  end

  # ---------------------------------------------------------------------------
  # FIN
  # ---------------------------------------------------------------------------
  print_section("Demo terminee!")

  puts <<-SUMMARY

  Resume:
  - SQLite adapter fonctionne avec vraie DB
  - Queries executees et resultats affiches
  - Associations (joins) fonctionnent
  - Validation et type checking actifs
  - Differences avec Postgres geres

  Pour utiliser SQLite dans votre projet:

    require "sqlite3"
    require "quo"

    DB.open "sqlite3:./my_database.db" do |db|
      adapter = Quo::Adapters::SQLite.new(db)
      results = MyRelation.new(adapter).active.to_a
    end

  SUMMARY
end
