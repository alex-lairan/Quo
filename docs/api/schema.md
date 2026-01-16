# Schema API

`Quo::Schema` defines table structure and associations.

## Schema Class

### Properties

```crystal
schema.table_name   : Symbol
schema.columns      : Hash(Symbol, Column)
schema.primary_key  : Symbol?
schema.associations : Hash(Symbol, Association)
```

### Methods

#### column

```crystal
def column(name : Symbol) : Column?
```

Get a column by name.

```crystal
col = schema.column(:name)
col.name       # => :name
col.type_name  # => "String"
```

#### has_column?

```crystal
def has_column?(name : Symbol) : Bool
```

Check if column exists.

```crystal
schema.has_column?(:email)  # => true
schema.has_column?(:foo)    # => false
```

#### association

```crystal
def association(name : Symbol) : Association?
```

Get an association by name.

```crystal
assoc = schema.association(:user)
assoc.name         # => :user
assoc.foreign_key  # => :user_id
assoc.target_table # => :users
```

#### has_association?

```crystal
def has_association?(name : Symbol) : Bool
```

Check if association exists.

#### column_names

```crystal
def column_names : Array(Symbol)
```

Get all column names.

```crystal
schema.column_names  # => [:id, :name, :email, :active]
```

---

## Column Class

### Properties

```crystal
column.name        : Symbol
column.type_name   : String
column.nullable?   : Bool
column.primary_key?: Bool
column.default     : DB::Any?
```

### Example

```crystal
schema :users do
  primary_key :id, Int64
  column :name, String
  column :score, Int32
end

id_col = schema.column(:id)
id_col.name          # => :id
id_col.type_name     # => "Int64"
id_col.primary_key?  # => true

name_col = schema.column(:name)
name_col.type_name   # => "String"
name_col.nullable?   # => false
```

---

## Association Classes

### BelongsTo

Foreign key is on **this** table.

```crystal
class BelongsTo < Association
  property name : Symbol
  property foreign_key : Symbol
  property target_table : Symbol
  property target_key : Symbol  # default: :id
end
```

```crystal
# posts.user_id -> users.id
belongs_to :user, :user_id, :users

# contracts.provider_uuid -> stripe.stripe_id
belongs_to :stripe, :provider_uuid, :stripe_subscriptions, :stripe_id
```

### HasMany

Foreign key is on the **other** table.

```crystal
class HasMany < Association
  property name : Symbol
  property foreign_key : Symbol
  property target_table : Symbol
  property source_key : Symbol  # default: :id
end
```

```crystal
# users.id <- posts.user_id
has_many :posts, :user_id, :posts
```

### HasOne

Same as HasMany but semantically single record.

```crystal
class HasOne < Association
  property name : Symbol
  property foreign_key : Symbol
  property target_table : Symbol
  property source_key : Symbol
end
```

```crystal
# users.id <- profiles.user_id
has_one :profile, :user_id, :profiles
```

---

## SchemaRegistry

Global registry of all schemas.

### register

```crystal
def self.register(schema : Schema) : Nil
```

Register a schema. Called automatically by the `schema` macro.

### get

```crystal
def self.get(table_name : Symbol) : Schema?
```

Get schema by table name.

```crystal
schema = Quo::SchemaRegistry.get(:users)
```

### get!

```crystal
def self.get!(table_name : Symbol) : Schema
```

Get schema or raise `SchemaError`.

### registered?

```crystal
def self.registered?(table_name : Symbol) : Bool
```

Check if schema exists.

```crystal
Quo::SchemaRegistry.registered?(:users)  # => true
```

### validate_column!

```crystal
def self.validate_column!(table_name : Symbol, column_name : Symbol) : Nil
```

Validate column exists. Raises `InvalidColumnError` if not.

```crystal
Quo::SchemaRegistry.validate_column!(:users, :email)      # OK
Quo::SchemaRegistry.validate_column!(:users, :nonexistent)  # Raises!
```

### validate_column_value!

```crystal
def self.validate_column_value!(table_name : Symbol, column_name : Symbol, value : DB::Any) : Nil
```

Validate column exists and value type matches. Raises `InvalidColumnError` or `TypeError`.

### tables

```crystal
def self.tables : Array(Symbol)
```

List all registered table names.

```crystal
Quo::SchemaRegistry.tables  # => [:users, :posts, :contracts]
```

### clear!

```crystal
def self.clear! : Nil
```

Clear all registered schemas. Useful for testing.

---

## Type Validation Rules

| Column Type | Accepts |
|-------------|---------|
| `String` | `String` only |
| `Int32` | `Int32`, `Int64` |
| `Int64` | `Int32`, `Int64` |
| `Float64` | `Float64`, `Float32`, `Int32`, `Int64` |
| `Bool` | `Bool` only |
| `Time` | `Time` only |

Unknown types pass validation for extensibility.
