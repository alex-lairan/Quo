# Changelog

All notable changes to Quo.

## [Unreleased]

## [0.1.0] - 2024

### Added

- **Core Query Builder**
  - Immutable `Query` class with chainable methods
  - Explicit table-qualified column references
  - SELECT, WHERE, ORDER BY, LIMIT, OFFSET, DISTINCT

- **Expression DSL**
  - Comparison operators: `==`, `!=`, `>`, `>=`, `<`, `<=`
  - String matching: `like`, `ilike`
  - Collection: `in`, `between`
  - NULL checks: `is_null`, `is_not_null`
  - Logical: `&` (AND), `|` (OR), `not`

- **Relations**
  - `Quo::Relation` base class
  - Schema definition with `schema` macro
  - Column definitions with type information
  - Primary key support

- **Scopes**
  - `scope` macro for reusable query fragments
  - Scopes with and without arguments
  - Scope composition

- **Associations**
  - `belongs_to` - foreign key on this table
  - `has_many` - foreign key on other table
  - `has_one` - single record relationship
  - Custom key support for non-standard joins
  - Association-based joins: `.join(:user)`

- **Validation**
  - Schema registry for global column validation
  - Runtime column existence checking
  - Type checking for values
  - Helpful error messages with available columns

- **Adapters**
  - `Quo::Adapters::Postgres` - PostgreSQL support
  - `Quo::Adapters::SQLite` - SQLite support
  - `Quo::Adapters::Test` - Testing without database

- **Join Support**
  - INNER, LEFT, RIGHT (Postgres), FULL (Postgres) joins
  - Association-based joins
  - Explicit join conditions

### Database Differences

| Feature | PostgreSQL | SQLite |
|---------|------------|--------|
| Placeholders | `$1, $2` | `?` |
| ILIKE | Native | `LOWER()` emulation |
| RIGHT JOIN | Yes | No |
| FULL JOIN | Yes | No |
