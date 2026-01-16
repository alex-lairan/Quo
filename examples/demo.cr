require "../src/quo"

# =============================================================================
# SCHEMA DEFINITIONS - 5 Tables avec Associations
# =============================================================================

class UsersRelation < Quo::Relation
  schema :users do
    primary_key :id, String
    column :email, String
    column :name, String
    column :role, String
    column :active, Bool
    column :created_at, Time
    column :updated_at, Time

    # Un user a plusieurs liaisons user_companies
    has_many :user_companies, :user_id, :user_companies
  end

  scope :active do
    query.where(users: {active: true})
  end

  scope :admins do
    query.where(users: {role: "admin"})
  end

  scope :by_email, email : String do
    query.where(users: {email: email})
  end

  scope :recent do
    query.order(users: {created_at: :desc})
  end
end

class CompaniesRelation < Quo::Relation
  schema :companies do
    primary_key :id, String
    column :name, String
    column :siret, String
    column :address, String
    column :city, String
    column :country, String
    column :active, Bool
    column :created_at, Time

    # Une company a plusieurs clients
    has_many :clients, :company_id, :clients
    # Une company a plusieurs contrats
    has_many :contracts, :company_id, :contracts
    # Une company a plusieurs liaisons user_companies
    has_many :user_companies, :company_id, :user_companies
  end

  scope :active do
    query.where(companies: {active: true})
  end

  scope :in_country, country : String do
    query.where(companies: {country: country})
  end

  scope :search_name, pattern : String do
    query.where { |e| e[:companies][:name].ilike(pattern) }
  end
end

class ClientsRelation < Quo::Relation
  schema :clients do
    primary_key :id, String
    column :company_id, String
    column :name, String
    column :email, String
    column :phone, String
    column :vip, Bool
    column :created_at, Time

    # Un client appartient à une company
    belongs_to :company, :company_id, :companies
    # Un client a plusieurs contrats
    has_many :contracts, :client_id, :contracts
  end

  scope :for_company, company_id : String do
    query.where(clients: {company_id: company_id})
  end

  scope :vip do
    query.where(clients: {vip: true})
  end

  scope :with_email do
    query.where { |e| e[:clients][:email].is_not_null }
  end
end

class ContractsRelation < Quo::Relation
  schema :contracts do
    primary_key :id, String
    column :reference, String
    column :client_id, String
    column :company_id, String
    column :user_id, String
    column :status, String
    column :monthly_amount_cents, Int64
    column :start_date, Time
    column :end_date, Time
    column :created_at, Time
    column :updated_at, Time
    # Exemple de clé custom: le provider externe utilise un ID différent
    column :payment_provider_uuid, String

    # Associations standard
    belongs_to :client, :client_id, :clients
    belongs_to :company, :company_id, :companies
    belongs_to :user, :user_id, :users

    # Association avec clé custom (comme ton exemple insurance_policies -> stripe_subscriptions)
    belongs_to :stripe_subscription, :payment_provider_uuid, :stripe_subscriptions, :stripe_id
  end

  scope :active do
    query.where(contracts: {status: "active"})
  end

  scope :pending do
    query.where(contracts: {status: "pending"})
  end

  scope :for_user, user_id : String do
    query.where(contracts: {user_id: user_id})
  end

  scope :for_company, company_id : String do
    query.where(contracts: {company_id: company_id})
  end

  scope :high_value, min_cents : Int64 do
    query.where { |e| e[:contracts][:monthly_amount_cents] >= min_cents }
  end

  scope :in_amount_range, min : Int64, max : Int64 do
    query.where { |e| e[:contracts][:monthly_amount_cents].between(min, max) }
  end

  scope :by_status, statuses : Array(String) do
    query.where { |e| e[:contracts][:status].in(statuses) }
  end

  scope :recent do
    query.order(contracts: {created_at: :desc})
  end
end

# Table de liaison User <-> Company avec les droits
class UserCompaniesRelation < Quo::Relation
  schema :user_companies do
    primary_key :id, String
    column :user_id, String
    column :company_id, String
    column :role, String          # admin, manager, viewer
    column :can_create, Bool
    column :can_edit, Bool
    column :can_delete, Bool
    column :can_validate, Bool
    column :created_at, Time

    # Associations
    belongs_to :user, :user_id, :users
    belongs_to :company, :company_id, :companies
  end

  scope :for_user, user_id : String do
    query.where(user_companies: {user_id: user_id})
  end

  scope :for_company, company_id : String do
    query.where(user_companies: {company_id: company_id})
  end

  scope :admins do
    query.where(user_companies: {role: "admin"})
  end

  scope :with_permission, permission : Symbol do
    case permission
    when :create
      query.where(user_companies: {can_create: true})
    when :edit
      query.where(user_companies: {can_edit: true})
    when :delete
      query.where(user_companies: {can_delete: true})
    when :validate
      query.where(user_companies: {can_validate: true})
    else
      query
    end
  end
end

# Table externe Stripe (pour démo de clé custom)
class StripeSubscriptionsRelation < Quo::Relation
  schema :stripe_subscriptions do
    primary_key :id, String
    column :stripe_id, String  # L'ID Stripe externe
    column :customer_email, String
    column :plan_name, String
    column :status, String
    column :created_at, Time
  end
end

# =============================================================================
# HELPER pour afficher les queries
# =============================================================================

def print_query(name : String, sql : String, params : Array(DB::Any))
  puts "\n#{"=" * 80}"
  puts "📋 #{name}"
  puts "=" * 80
  puts "\n🔹 SQL:"
  puts sql
  puts "\n🔹 Params: #{params.inspect}"
end

# =============================================================================
# EXEMPLES DE QUERIES
# =============================================================================

adapter = Quo::Adapters::Test.new

puts "\n" + "🚀 QUO - Query Builder Demo ".ljust(80, '=')
puts "Démonstration avec 5 tables + associations"
puts ""
puts "🆕 NOUVELLE FEATURE: Association Joins"
puts "   Plus besoin de spécifier les colonnes de jointure!"
puts "   .join(:user) au lieu de .join(:users, on: {contracts: :user_id, eq: {users: :id}})"

# -----------------------------------------------------------------------------
# PARTIE 1: ASSOCIATION JOINS (NOUVELLE FEATURE)
# -----------------------------------------------------------------------------

puts "\n" + "=" * 80
puts "📦 PARTIE 1: ASSOCIATION JOINS"
puts "=" * 80

# -----------------------------------------------------------------------------
# 1. Join simple avec association
# -----------------------------------------------------------------------------
sql, params = ContractsRelation.new(adapter)
  .select(contracts: [:id, :reference, :status], users: [:name, :email])
  .join(:user)  # 🆕 Utilise l'association belongs_to :user
  .active
  .to_sql

print_query(
  "1. JOIN via association - .join(:user)",
  sql, params
)

# -----------------------------------------------------------------------------
# 2. Plusieurs joins via associations
# -----------------------------------------------------------------------------
sql, params = ContractsRelation.new(adapter)
  .select(
    contracts: [:id, :reference],
    users: [:name],
    companies: [:name],
    clients: [:name, :email]
  )
  .join(:user)      # 🆕 contracts.user_id = users.id
  .join(:company)   # 🆕 contracts.company_id = companies.id
  .join(:client)    # 🆕 contracts.client_id = clients.id
  .active
  .to_sql

print_query(
  "2. Multiples JOINs via associations - .join(:user).join(:company).join(:client)",
  sql, params
)

# -----------------------------------------------------------------------------
# 3. LEFT JOIN via association
# -----------------------------------------------------------------------------
sql, params = ContractsRelation.new(adapter)
  .select(contracts: [:id, :reference], clients: [:name, :vip])
  .left_join(:client)  # 🆕 LEFT JOIN via association
  .active
  .to_sql

print_query(
  "3. LEFT JOIN via association - .left_join(:client)",
  sql, params
)

# -----------------------------------------------------------------------------
# 4. Association avec clé custom (comme ton exemple insurance_policies -> stripe)
# -----------------------------------------------------------------------------
sql, params = ContractsRelation.new(adapter)
  .select(
    contracts: [:id, :reference, :payment_provider_uuid],
    stripe_subscriptions: [:stripe_id, :plan_name, :status]
  )
  .join(:stripe_subscription)  # 🆕 contracts.payment_provider_uuid = stripe_subscriptions.stripe_id
  .active
  .to_sql

print_query(
  "4. JOIN avec clé custom - .join(:stripe_subscription)\n   (payment_provider_uuid -> stripe_id)",
  sql, params
)

# -----------------------------------------------------------------------------
# 5. has_many join
# -----------------------------------------------------------------------------
sql, params = CompaniesRelation.new(adapter)
  .select(companies: [:id, :name], clients: [:name, :email])
  .join(:clients)  # 🆕 has_many - companies.id = clients.company_id
  .active
  .to_sql

print_query(
  "5. JOIN has_many - .join(:clients)",
  sql, params
)

# -----------------------------------------------------------------------------
# 6. Mix: association joins + explicit join
# -----------------------------------------------------------------------------
sql, params = ContractsRelation.new(adapter)
  .join(:user)  # 🆕 Association
  .join(:audit_logs, on: {contracts: :id, eq: {audit_logs: :contract_id}})  # Explicit
  .to_sql

print_query(
  "6. Mix association + explicit join",
  sql, params
)

# -----------------------------------------------------------------------------
# PARTIE 2: QUERIES COMPLEXES (comme avant, mais avec associations)
# -----------------------------------------------------------------------------

puts "\n" + "=" * 80
puts "📦 PARTIE 2: QUERIES COMPLEXES AVEC ASSOCIATIONS"
puts "=" * 80

# -----------------------------------------------------------------------------
# 7. Dashboard admin avec associations
# -----------------------------------------------------------------------------
sql, params = ContractsRelation.new(adapter)
  .select(
    contracts: [:id, :reference, :status, :monthly_amount_cents],
    users: [:name, :email],
    companies: [:name, :siret],
    clients: [:name, :vip]
  )
  .join(:user)
  .join(:company)
  .left_join(:client)  # LEFT JOIN car client peut être null
  .where { |e|
    (e[:contracts][:status] == "active") | (e[:contracts][:status] == "pending")
  }
  .where { |e| e[:contracts][:monthly_amount_cents] >= 5_000 }
  .where { |e| e[:companies][:active] == true }
  .order(contracts: {monthly_amount_cents: :desc})
  .limit(100)
  .distinct
  .to_sql

print_query(
  "7. Dashboard admin - Query complexe avec associations",
  sql, params
)

# -----------------------------------------------------------------------------
# 8. User permissions via join table
# -----------------------------------------------------------------------------
sql, params = UserCompaniesRelation.new(adapter)
  .select(
    user_companies: [:role, :can_create, :can_edit, :can_delete, :can_validate],
    users: [:name, :email],
    companies: [:name]
  )
  .join(:user)     # 🆕 user_companies.user_id = users.id
  .join(:company)  # 🆕 user_companies.company_id = companies.id
  .for_user("user-123-uuid")
  .for_company("company-456-uuid")
  .to_sql

print_query(
  "8. Permissions user dans company - via associations",
  sql, params
)

# -----------------------------------------------------------------------------
# 9. Clients VIP avec leurs contrats
# -----------------------------------------------------------------------------
sql, params = ClientsRelation.new(adapter)
  .select(
    clients: [:id, :name, :email, :vip],
    contracts: [:reference, :status, :monthly_amount_cents],
    companies: [:name]
  )
  .join(:company)    # 🆕 belongs_to
  .join(:contracts)  # 🆕 has_many
  .vip
  .where(contracts: {status: "active"})
  .order(clients: {name: :asc})
  .to_sql

print_query(
  "9. Clients VIP avec contrats actifs - via associations",
  sql, params
)

# -----------------------------------------------------------------------------
# 10. Contrats avec paiement Stripe
# -----------------------------------------------------------------------------
sql, params = ContractsRelation.new(adapter)
  .select(
    contracts: [:id, :reference, :monthly_amount_cents],
    stripe_subscriptions: [:stripe_id, :plan_name, :status]
  )
  .join(:stripe_subscription)  # 🆕 Clé custom!
  .where { |e| e[:stripe_subscriptions][:status] == "active" }
  .where { |e| e[:contracts][:monthly_amount_cents] >= 10_000 }
  .to_sql

print_query(
  "10. Contrats avec Stripe subscription active (clé custom)",
  sql, params
)

# -----------------------------------------------------------------------------
# PARTIE 3: COMPARAISON AVANT/APRÈS
# -----------------------------------------------------------------------------

puts "\n" + "=" * 80
puts "📦 PARTIE 3: COMPARAISON AVANT/APRÈS"
puts "=" * 80

# AVANT (explicit join)
sql_before, _ = ContractsRelation.new(adapter)
  .join(:users, on: {contracts: :user_id, eq: {users: :id}})
  .join(:companies, on: {contracts: :company_id, eq: {companies: :id}})
  .join(:clients, on: {contracts: :client_id, eq: {clients: :id}})
  .to_sql

# APRÈS (association join)
sql_after, _ = ContractsRelation.new(adapter)
  .join(:user)
  .join(:company)
  .join(:client)
  .to_sql

puts "\n" + "=" * 80
puts "📋 AVANT (explicit joins):"
puts "=" * 80
puts <<-CODE

ContractsRelation.new(adapter)
  .join(:users, on: {contracts: :user_id, eq: {users: :id}})
  .join(:companies, on: {contracts: :company_id, eq: {companies: :id}})
  .join(:clients, on: {contracts: :client_id, eq: {clients: :id}})

CODE
puts "🔹 SQL: #{sql_before}"

puts "\n" + "=" * 80
puts "📋 APRÈS (association joins):"
puts "=" * 80
puts <<-CODE

ContractsRelation.new(adapter)
  .join(:user)
  .join(:company)
  .join(:client)

CODE
puts "🔹 SQL: #{sql_after}"

puts "\n✅ Même SQL généré, code beaucoup plus lisible!"

# -----------------------------------------------------------------------------
# RÉSUMÉ
# -----------------------------------------------------------------------------

puts "\n" + "=" * 80
puts "✅ Démonstration terminée"
puts "=" * 80
puts <<-SUMMARY

📌 Association Syntax:
   belongs_to :user, :user_id, :users                    # Standard (target_key = :id)
   belongs_to :subscription, :provider_uuid, :stripe, :stripe_id  # Custom key

   has_many :invoices, :contract_id, :invoices          # Standard
   has_one :profile, :user_id, :profiles                # Single record

📌 Usage:
   .join(:user)       # INNER JOIN via association
   .left_join(:user)  # LEFT JOIN via association
   .right_join(:user) # RIGHT JOIN via association

📌 Explicit join still works:
   .join(:users, on: {contracts: :user_id, eq: {users: :id}})

SUMMARY

# -----------------------------------------------------------------------------
# PARTIE 4: VALIDATION ET TYPE CHECKING (NOUVELLE FEATURE)
# -----------------------------------------------------------------------------

puts "\n" + "=" * 80
puts "📦 PARTIE 4: VALIDATION ET TYPE CHECKING"
puts "=" * 80

puts "\n🆕 NOUVELLE FEATURE: Validation des colonnes et type checking"
puts "   Les colonnes sont validées contre le schema!"
puts "   Les types des valeurs sont vérifiés!"

# -----------------------------------------------------------------------------
# 11. Validation OK - colonnes existantes
# -----------------------------------------------------------------------------
sql, params = ContractsRelation.new(adapter)
  .select(contracts: [:id, :reference, :status])  # ✅ Colonnes valides
  .where(contracts: {status: "active"})            # ✅ String pour colonne String
  .where(contracts: {monthly_amount_cents: 5000_i64})  # ✅ Int64 pour colonne Int64
  .order(contracts: {created_at: :desc})           # ✅ Colonne valide
  .to_sql

print_query(
  "11. Validation OK - Toutes les colonnes et types sont corrects",
  sql, params
)

# -----------------------------------------------------------------------------
# 12. Validation OK avec joins et expressions
# -----------------------------------------------------------------------------
sql, params = ContractsRelation.new(adapter)
  .select(contracts: [:id, :reference], users: [:name, :email])
  .join(:user)
  .where { |e|
    (e[:contracts][:status] == "active") &  # ✅ Colonne contracts.status existe
    (e[:users][:active] == true)             # ✅ Colonne users.active existe
  }
  .where { |e| e[:contracts][:monthly_amount_cents].between(1000_i64, 10000_i64) }  # ✅ Type OK
  .to_sql

print_query(
  "12. Validation OK avec joins - colonnes des tables jointes validées",
  sql, params
)

# -----------------------------------------------------------------------------
# 13. Démonstration des erreurs de validation
# -----------------------------------------------------------------------------
puts "\n" + "=" * 80
puts "📋 13. Démonstration des erreurs de validation"
puts "=" * 80

# Erreur 1: Colonne inexistante dans select
puts "\n🔴 Test 1: Colonne inexistante dans select"
puts "   Code: .select(contracts: [:id, :nonexistent_column])"
begin
  ContractsRelation.new(adapter)
    .select(contracts: [:id, :nonexistent_column])
    .to_sql
rescue ex : Quo::InvalidColumnError
  puts "   ✅ Erreur capturée: #{ex.message}"
end

# Erreur 2: Colonne inexistante dans where hash
puts "\n🔴 Test 2: Colonne inexistante dans where"
puts "   Code: .where(contracts: {bad_column: \"value\"})"
begin
  ContractsRelation.new(adapter)
    .where(contracts: {bad_column: "value"})
    .to_sql
rescue ex : Quo::InvalidColumnError
  puts "   ✅ Erreur capturée: #{ex.message}"
end

# Erreur 3: Colonne inexistante dans order
puts "\n🔴 Test 3: Colonne inexistante dans order"
puts "   Code: .order(contracts: {fake_date: :desc})"
begin
  ContractsRelation.new(adapter)
    .order(contracts: {fake_date: :desc})
    .to_sql
rescue ex : Quo::InvalidColumnError
  puts "   ✅ Erreur capturée: #{ex.message}"
end

# Erreur 4: Colonne inexistante dans expression
puts "\n🔴 Test 4: Colonne inexistante dans expression"
puts "   Code: .where { |e| e[:contracts][:unknown] == \"x\" }"
begin
  ContractsRelation.new(adapter)
    .where { |e| e[:contracts][:unknown] == "x" }
    .to_sql
rescue ex : Quo::InvalidColumnError
  puts "   ✅ Erreur capturée: #{ex.message}"
end

# Erreur 5: Type mismatch - String pour Int64
puts "\n🔴 Test 5: Type mismatch - String au lieu de Int64"
puts "   Code: .where(contracts: {monthly_amount_cents: \"not a number\"})"
begin
  ContractsRelation.new(adapter)
    .where(contracts: {monthly_amount_cents: "not a number"})
    .to_sql
rescue ex : Quo::TypeError
  puts "   ✅ Erreur capturée: #{ex.message}"
end

# Erreur 6: Type mismatch - Int pour String
puts "\n🔴 Test 6: Type mismatch - Int au lieu de String"
puts "   Code: .where(contracts: {status: 123})"
begin
  ContractsRelation.new(adapter)
    .where(contracts: {status: 123})
    .to_sql
rescue ex : Quo::TypeError
  puts "   ✅ Erreur capturée: #{ex.message}"
end

# Erreur 7: Type mismatch - String pour Bool
puts "\n🔴 Test 7: Type mismatch - String au lieu de Bool"
puts "   Code: .where(users: {active: \"yes\"})"
begin
  UsersRelation.new(adapter)
    .where(users: {active: "yes"})
    .to_sql
rescue ex : Quo::TypeError
  puts "   ✅ Erreur capturée: #{ex.message}"
end

# Erreur 8: Type mismatch dans expression
puts "\n🔴 Test 8: Type mismatch dans expression"
puts "   Code: .where { |e| e[:contracts][:monthly_amount_cents] >= \"invalid\" }"
begin
  ContractsRelation.new(adapter)
    .where { |e| e[:contracts][:monthly_amount_cents] >= "invalid" }
    .to_sql
rescue ex : Quo::TypeError
  puts "   ✅ Erreur capturée: #{ex.message}"
end

# Erreur 9: Colonne inexistante dans table jointe
puts "\n🔴 Test 9: Colonne inexistante dans table jointe"
puts "   Code: .join(:user).select(users: [:nonexistent])"
begin
  ContractsRelation.new(adapter)
    .join(:user)
    .select(users: [:nonexistent])
    .to_sql
rescue ex : Quo::InvalidColumnError
  puts "   ✅ Erreur capturée: #{ex.message}"
end

# Type widening OK - Int32 vers Int64
puts "\n🟢 Test 10: Type widening OK (Int32 pour colonne Int64)"
puts "   Code: .where(contracts: {monthly_amount_cents: 1000})"
sql, params = ContractsRelation.new(adapter)
  .where(contracts: {monthly_amount_cents: 1000})  # Int32 accepté pour Int64
  .to_sql
puts "   ✅ Accepté! SQL: #{sql}"

# Tables non enregistrées (flexibility)
puts "\n🟢 Test 11: Tables non enregistrées (flexibilité)"
puts "   Code: .join(:external_table, ...).select(external_table: [:any_column])"
sql, params = ContractsRelation.new(adapter)
  .join(:external_api, on: {contracts: :id, eq: {external_api: :contract_id}})
  .select(external_api: [:any_column])  # Pas d'erreur - table non enregistrée
  .to_sql
puts "   ✅ Accepté! Les tables non enregistrées ne sont pas validées"
puts "   SQL: #{sql}"

# -----------------------------------------------------------------------------
# RÉSUMÉ VALIDATION
# -----------------------------------------------------------------------------

puts "\n" + "=" * 80
puts "✅ Validation Summary"
puts "=" * 80
puts <<-VALIDATION_SUMMARY

📌 Column Validation:
   - Validates columns exist in registered schemas
   - Works in: select, where (hash & expression), order
   - Validates columns from joined tables too
   - Skips validation for unregistered tables (flexibility)

📌 Type Checking:
   - String column expects String value
   - Int64 column accepts Int32 or Int64 (widening)
   - Float64 accepts Float64, Float32, Int32, Int64
   - Bool column expects Bool value
   - Time column expects Time value

📌 Errors:
   - Quo::InvalidColumnError for missing columns
   - Quo::TypeError for type mismatches

📌 Benefits:
   - Catch typos at runtime, not in SQL execution
   - Clear error messages with available columns listed
   - Type safety without compile-time overhead

VALIDATION_SUMMARY
