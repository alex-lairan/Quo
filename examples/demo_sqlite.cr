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
  # QUERIES SIMPLES - Direct .to_a
  # ---------------------------------------------------------------------------
  print_section("3. Queries simples (.to_a direct)")

  # 3.1 - Tous les users actifs
  puts "\n3.1 Tous les users actifs:"
  results = UsersRelation.new(adapter)
    .select(users: [:id, :name, :email, :role])
    .active
    .to_a
  print_results(results)

  # 3.2 - Users admin
  puts "\n3.2 Users admin:"
  results = UsersRelation.new(adapter)
    .select(users: [:id, :name, :role])
    .admins
    .to_a
  print_results(results)

  # 3.3 - Companies en France
  puts "\n3.3 Companies en France:"
  results = CompaniesRelation.new(adapter)
    .select(companies: [:id, :name, :country])
    .in_country("France")
    .to_a
  print_results(results)

  # ---------------------------------------------------------------------------
  # TERMINAL METHODS: first, first!, count, exists?
  # ---------------------------------------------------------------------------
  print_section("4. Terminal methods")

  # 4.1 - first (returns nil if not found)
  puts "\n4.1 Premier admin:"
  user = UsersRelation.new(adapter)
    .select(users: [:id, :name])
    .admins
    .first
  puts "  #{user}"

  # 4.2 - first! (raises if not found)
  puts "\n4.2 Premier contract actif (first!):"
  contract = ContractsRelation.new(adapter)
    .select(contracts: [:id, :reference])
    .active
    .first!
  puts "  #{contract}"

  # 4.3 - count
  puts "\n4.3 Nombre de contracts actifs:"
  count = ContractsRelation.new(adapter).active.count
  puts "  Count: #{count}"

  # 4.4 - exists?
  puts "\n4.4 Existe-t-il des users admin?"
  exists = UsersRelation.new(adapter).admins.exists?
  puts "  Exists: #{exists}"

  # ---------------------------------------------------------------------------
  # QUERIES AVEC EXPRESSIONS
  # ---------------------------------------------------------------------------
  print_section("5. Queries avec expressions")

  # 5.1 - Contracts avec montant >= 50000
  puts "\n5.1 Contracts high value (>= 500 EUR):"
  results = ContractsRelation.new(adapter)
    .select(contracts: [:id, :reference, :amount_cents, :status])
    .high_value(50000_i64)
    .to_a
  print_results(results)

  # 5.2 - Contracts actifs OU pending
  puts "\n5.2 Contracts actifs OU pending:"
  results = ContractsRelation.new(adapter)
    .select(contracts: [:id, :reference, :status])
    .where { |e|
      (e[:contracts][:status] == "active") | (e[:contracts][:status] == "pending")
    }
    .to_a
  print_results(results)

  # 5.3 - Contracts avec montant entre 20000 et 80000
  puts "\n5.3 Contracts avec montant entre 200 et 800 EUR:"
  results = ContractsRelation.new(adapter)
    .select(contracts: [:id, :reference, :amount_cents])
    .where { |e| e[:contracts][:amount_cents].between(20000_i64, 80000_i64) }
    .to_a
  print_results(results)

  # 5.4 - IN clause
  puts "\n5.4 Contracts avec status IN ('active', 'pending'):"
  results = ContractsRelation.new(adapter)
    .select(contracts: [:id, :reference, :status])
    .where { |e| e[:contracts][:status].in(["active", "pending"]) }
    .to_a
  print_results(results)

  # ---------------------------------------------------------------------------
  # QUERIES AVEC JOINS (via associations)
  # ---------------------------------------------------------------------------
  print_section("6. Queries avec JOINs (associations)")

  # 6.1 - Contracts avec user (INNER JOIN)
  puts "\n6.1 Contracts actifs avec info user:"
  results = ContractsRelation.new(adapter)
    .select(contracts: [:id, :reference, :status], users: [:name, :email])
    .join(:user)
    .active
    .to_a
  print_results(results)

  # 6.2 - Contracts avec user ET company
  puts "\n6.2 Tous les contracts avec user ET company:"
  results = ContractsRelation.new(adapter)
    .select(
      contracts: [:reference, :amount_cents],
      users: [:name],
      companies: [:name, :country]
    )
    .join(:user)
    .join(:company)
    .to_a
  print_results(results)

  # 6.3 - LEFT JOIN
  puts "\n6.3 Tous les contracts (LEFT JOIN user):"
  results = ContractsRelation.new(adapter)
    .select(contracts: [:id, :reference], users: [:name])
    .left_join(:user)
    .to_a
  print_results(results)

  # ---------------------------------------------------------------------------
  # QUERY COMPLEXE
  # ---------------------------------------------------------------------------
  print_section("7. Query complexe - Dashboard")

  puts "\nContracts actifs high value avec user et company actifs:"
  results = ContractsRelation.new(adapter)
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
    .to_a
  print_results(results)

  # ---------------------------------------------------------------------------
  # ILIKE (case-insensitive)
  # ---------------------------------------------------------------------------
  print_section("8. Recherche case-insensitive (ILIKE)")

  puts "\nRecherche '%martin%' (case-insensitive):"
  results = UsersRelation.new(adapter)
    .select(users: [:id, :name, :email])
    .where { |e| e[:users][:name].ilike("%martin%") }
    .to_a
  print_results(results)

  # ---------------------------------------------------------------------------
  # CHAINING EXAMPLE
  # ---------------------------------------------------------------------------
  print_section("9. Chaining fluide")

  puts <<-CODE

  # Le code devient tres lisible:

  results = ContractsRelation.new(adapter)
    .select(contracts: [:reference], users: [:name])
    .join(:user)
    .active
    .high_value(50000_i64)
    .order(contracts: {amount_cents: :desc})
    .limit(5)
    .to_a

  CODE

  results = ContractsRelation.new(adapter)
    .select(contracts: [:reference], users: [:name])
    .join(:user)
    .active
    .high_value(50000_i64)
    .order(contracts: {amount_cents: :desc})
    .limit(5)
    .to_a
  print_results(results)

  # ---------------------------------------------------------------------------
  # VALIDATION ERRORS
  # ---------------------------------------------------------------------------
  print_section("10. Validation")

  puts "\n10.1 Erreur colonne inexistante:"
  begin
    UsersRelation.new(adapter)
      .select(users: [:id, :nonexistent])
      .to_a
  rescue ex : Quo::InvalidColumnError
    puts "  Erreur: #{ex.message}"
  end

  puts "\n10.2 Erreur type mismatch:"
  begin
    ContractsRelation.new(adapter)
      .where(contracts: {amount_cents: "not a number"})
      .to_a
  rescue ex : Quo::TypeError
    puts "  Erreur: #{ex.message}"
  end

  # ---------------------------------------------------------------------------
  # FIN
  # ---------------------------------------------------------------------------
  print_section("Demo terminee!")

  puts <<-SUMMARY

  API simplifiee:

    # Execution directe
    results = MyRelation.new(adapter).active.to_a

    # Premier resultat
    user = UsersRelation.new(adapter).admins.first

    # Premier ou erreur
    contract = ContractsRelation.new(adapter).active.first!

    # Comptage
    count = ContractsRelation.new(adapter).active.count

    # Existence
    exists = UsersRelation.new(adapter).admins.exists?

  SUMMARY
end
