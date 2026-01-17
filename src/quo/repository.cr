module Quo
  # Base class for repositories using Quo relations
  #
  # Provides:
  # - Access to the adapter for write operations
  # - `relation` macro to declare relation accessors
  # - CRUD shortcuts for common operations
  # - `entity` macro for declarative row-to-entity mapping
  # - Transaction wrapper for simplified transaction handling
  #
  # Example:
  #   class AccountRepository < Quo::Repository
  #     relation :accounts, AccountsRelation
  #
  #     entity :account, Account do
  #       map :id, Int64
  #       map :email, String
  #       map :status, Int32, ->(v : Int32) { AccountStatus.new(v) }
  #     end
  #
  #     def find_by_email(email : String) : Account?
  #       accounts.active.by_email(email).first.try { |row| account_from_row(row) }
  #     end
  #
  #     def create(email : String) : Account?
  #       insert_returning(:accounts, [:id, :email, :status],
  #         email: email, status: 0
  #       ).try { |row| account_from_row(row) }
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

    # =========================================================================
    # CRUD Shortcuts
    # =========================================================================

    # Insert a single record and return the number of affected rows
    #
    # Example:
    #   insert(:users, name: "Alice", email: "alice@example.com")
    def insert(table : Symbol, **values) : Int64
      InsertQuery.new(table, @adapter)
        .values(**values)
        .execute
    end

    # Insert a single record and return the inserted row (PostgreSQL RETURNING)
    #
    # Example:
    #   insert_returning(:users, [:id, :created_at], name: "Alice", email: "alice@example.com")
    def insert_returning(table : Symbol, returning : Array(Symbol), **values) : Row?
      # Build returning columns directly
      returning_cols = returning.map { |col| ColumnRef.new(table, col) }
      # Build values hash
      vals = {} of Symbol => DB::Any
      values.each { |k, v| vals[k] = v.as(DB::Any) }
      # Create query with returning columns
      InsertQuery.new(
        table: table,
        adapter: @adapter,
        values_list: [vals],
        returning_columns: returning_cols
      ).execute_returning_one
    end

    # Update records matching the where condition
    # Returns the number of affected rows
    #
    # Example:
    #   update(:users, {id: 123}, name: "Bob", updated_at: Time.utc)
    def update(table : Symbol, where : NamedTuple, **values) : Int64
      # Build where expressions directly
      where_clauses = [] of Expression
      where.each do |column, value|
        col_ref = ColumnRef.new(table, column)
        where_clauses << Eq.new(col_ref, value.as(DB::Any))
      end
      # Build set values
      set_values = {} of Symbol => DB::Any
      values.each { |k, v| set_values[k] = v.as(DB::Any) }
      # Create query
      UpdateQuery.new(
        table: table,
        adapter: @adapter,
        set_values: set_values,
        where_clauses: where_clauses
      ).execute
    end

    # Delete records matching the where condition
    # Returns the number of affected rows
    #
    # Example:
    #   delete(:users, id: 123)
    def delete(table : Symbol, **where) : Int64
      # Build where expressions directly
      where_clauses = [] of Expression
      where.each do |column, value|
        col_ref = ColumnRef.new(table, column)
        where_clauses << Eq.new(col_ref, value.as(DB::Any))
      end
      # Create query
      DeleteQuery.new(
        table: table,
        adapter: @adapter,
        where_clauses: where_clauses
      ).execute
    end

    # =========================================================================
    # Finder Helpers
    # =========================================================================

    # Find a record by primary key
    #
    # Example:
    #   find(:users, 123)  # => Row?
    def find(table : Symbol, id, primary_key : Symbol = :id) : Row?
      Query.new(table, @adapter)
        .where(**{table => {primary_key => id}})
        .first
    end

    # Find a record by arbitrary columns
    #
    # Example:
    #   find_by(:users, email: "test@example.com")  # => Row?
    def find_by(table : Symbol, **conditions) : Row?
      Query.new(table, @adapter)
        .where(**{table => conditions})
        .first
    end

    # Check if a record exists matching conditions
    #
    # Example:
    #   exists?(:users, email: "test@example.com")  # => Bool
    def exists?(table : Symbol, **conditions) : Bool
      Query.new(table, @adapter)
        .where(**{table => conditions})
        .exists?
    end

    # =========================================================================
    # Transaction Wrapper
    # =========================================================================

    # Execute a block within a database transaction
    # Commits on success, rolls back on exception
    #
    # Example:
    #   transaction do |tx|
    #     tx.insert(:accounts).values(email: "user@example.com").execute
    #     tx.insert(:profiles).values(account_id: 1, name: "User").execute
    #   end
    def transaction(isolation : IsolationLevel? = nil, &block : Transaction ->)
      @adapter.transaction(isolation) do |tx|
        yield tx
      end
    end

    # =========================================================================
    # Raw SQL Execution
    # =========================================================================

    # Execute raw SQL and return all results
    #
    # Example:
    #   execute("SELECT * FROM users WHERE status = $1", [1])
    def execute(sql : String, params : Array(DB::Any) = [] of DB::Any) : ResultSet
      @adapter.execute(sql, params)
    end

    # Execute raw SQL and return the first row
    #
    # Example:
    #   execute_one("SELECT * FROM users WHERE id = $1", [123])
    def execute_one(sql : String, params : Array(DB::Any) = [] of DB::Any) : Row?
      @adapter.execute(sql, params).first?
    end

    # =========================================================================
    # Entity Mapping Macro
    # =========================================================================

    # Macro to declare entity mappings from database rows to domain objects
    #
    # Generates two methods:
    # - `{name}_from_row(row : Row) : Entity` - convert a single row
    # - `{name.pluralize}_from_rows(rows : ResultSet) : Array(Entity)` - convert multiple rows
    #
    # Usage:
    #   entity :account, Account do
    #     map :id, Int64
    #     map :email, String
    #     map :status, Int32, ->(v : Int32) { AccountStatus.new(v) }
    #     map :created_at, Time
    #   end
    #
    # With transform (for custom type conversion):
    #   map :status, Int32, ->(v : Int32) { AccountStatus.new(v) }
    #
    # The transform proc receives the raw value and should return the desired type.
    macro entity(name, klass, &block)
      # Generate the single-row mapping method
      def {{name.id}}_from_row(row : Quo::Row) : {{klass}}
        {{klass}}.new(
          {% if block %}
            {% if block.body.is_a?(Expressions) %}
              {% for expr in block.body.expressions %}
                {% if expr.is_a?(Call) && expr.name == "map" %}
                  {% col = expr.args[0] %}
                  {% type = expr.args[1] %}
                  {% col_name = col.id.stringify %}
                  {% if expr.args.size > 2 %}
                    {{col.id}}: ({{expr.args[2]}}).call(row[{{col_name}}].as({{type}})),
                  {% else %}
                    {{col.id}}: row[{{col_name}}].as({{type}}),
                  {% end %}
                {% end %}
              {% end %}
            {% elsif block.body.is_a?(Call) && block.body.name == "map" %}
              {% expr = block.body %}
              {% col = expr.args[0] %}
              {% type = expr.args[1] %}
              {% col_name = col.id.stringify %}
              {% if expr.args.size > 2 %}
                {{col.id}}: ({{expr.args[2]}}).call(row[{{col_name}}].as({{type}})),
              {% else %}
                {{col.id}}: row[{{col_name}}].as({{type}}),
              {% end %}
            {% end %}
          {% end %}
        )
      end

      # Generate the result-set mapping method
      def {{name.id}}s_from_rows(rows : Quo::ResultSet) : Array({{klass}})
        rows.map { |row| {{name.id}}_from_row(row) }
      end
    end

    # =========================================================================
    # Complex Aggregate Mapping Patterns
    # =========================================================================
    #
    # The `entity` macro above works well for flat mappings (single table rows).
    # For complex aggregates with nested objects or collections, no single approach
    # fits all cases. Choose the pattern that matches your performance needs
    # and query complexity.
    #
    # ## Pattern Comparison
    #
    # | Pattern              | When to Use                        | Pros                              | Cons                              |
    # |----------------------|------------------------------------|-----------------------------------|-----------------------------------|
    # | array_agg/json_agg   | PostgreSQL, clean nested data      | Grouping in SQL, simple mapping   | PG-specific, JSON parsing overhead|
    # | JOIN + row grouping  | Portable, control over mapping     | Works everywhere, full control    | More Crystal code, memory for dupes|
    # | Separate queries     | Complex aggregates, caching        | Simple queries, cacheable         | N+1 risk, more round-trips        |
    # | SoA (Struct of Arrays)| Performance-critical              | Cache-friendly, vectorizable      | Less intuitive API                |
    #
    # -------------------------------------------------------------------------
    # Pattern 1: PostgreSQL array_agg
    # -------------------------------------------------------------------------
    #
    # Aggregation happens in SQL. Each row = one aggregate.
    #
    # ```crystal
    # def find_order_with_items(order_id : Int64) : Order?
    #   row = execute_one(<<-SQL, [order_id])
    #     SELECT
    #       o.id, o.total_cents,
    #       c.id as customer_id, c.name as customer_name, c.email as customer_email,
    #       array_agg(i.id) as item_ids,
    #       array_agg(i.product_id) as item_product_ids,
    #       array_agg(i.quantity) as item_quantities
    #     FROM orders o
    #     JOIN customers c ON o.customer_id = c.id
    #     LEFT JOIN order_items i ON i.order_id = o.id
    #     WHERE o.id = $1
    #     GROUP BY o.id, c.id
    #   SQL
    #
    #   return nil unless row
    #   build_order_from_aggregated_row(row)
    # end
    #
    # private def build_order_from_aggregated_row(row : Row) : Order
    #   # Arrays come back as PG arrays
    #   item_ids = row["item_ids"].as(Array(Int64?))
    #   product_ids = row["item_product_ids"].as(Array(Int64?))
    #   quantities = row["item_quantities"].as(Array(Int32?))
    #
    #   items = item_ids.zip(product_ids, quantities).compact_map do |(id, prod, qty)|
    #     next nil if id.nil?  # NULL from LEFT JOIN
    #     OrderItem.new(id: id, product_id: prod.not_nil!, quantity: qty.not_nil!)
    #   end
    #
    #   Order.new(
    #     id: row["id"].as(Int64),
    #     total_cents: row["total_cents"].as(Int64),
    #     customer: Customer.new(
    #       id: row["customer_id"].as(Int64),
    #       name: row["customer_name"].as(String),
    #       email: row["customer_email"].as(String)
    #     ),
    #     items: items
    #   )
    # end
    # ```
    #
    # -------------------------------------------------------------------------
    # Pattern 2: PostgreSQL json_agg
    # -------------------------------------------------------------------------
    #
    # Returns nested JSON, parse into objects.
    #
    # ```crystal
    # def find_order_with_items_json(order_id : Int64) : Order?
    #   row = execute_one(<<-SQL, [order_id])
    #     SELECT
    #       o.id, o.total_cents,
    #       json_build_object('id', c.id, 'name', c.name, 'email', c.email) as customer,
    #       COALESCE(json_agg(json_build_object('id', i.id, 'product_id', i.product_id, 'quantity', i.quantity))
    #                FILTER (WHERE i.id IS NOT NULL), '[]') as items
    #     FROM orders o
    #     JOIN customers c ON o.customer_id = c.id
    #     LEFT JOIN order_items i ON i.order_id = o.id
    #     WHERE o.id = $1
    #     GROUP BY o.id, c.id
    #   SQL
    #
    #   return nil unless row
    #
    #   # Parse JSON columns
    #   customer_json = JSON.parse(row["customer"].as(String))
    #   items_json = JSON.parse(row["items"].as(String))
    #
    #   Order.new(
    #     id: row["id"].as(Int64),
    #     total_cents: row["total_cents"].as(Int64),
    #     customer: Customer.from_json(customer_json),
    #     items: items_json.as_a.map { |j| OrderItem.from_json(j) }
    #   )
    # end
    # ```
    #
    # -------------------------------------------------------------------------
    # Pattern 3: JOIN + Row Grouping (Portable)
    # -------------------------------------------------------------------------
    #
    # Works with any database. Grouping happens in Crystal.
    #
    # ```crystal
    # def find_order_with_items(order_id : Int64) : Order?
    #   rows = orders
    #     .where(orders: {id: order_id})
    #     .join(:customer)
    #     .left_join(:order_items)
    #     .select(
    #       orders: [:id, :total_cents],
    #       customers: [:id, :name, :email],
    #       order_items: [:id, :product_id, :quantity]
    #     )
    #     .to_a
    #
    #   build_order_from_rows(rows)
    # end
    #
    # private def build_order_from_rows(rows : ResultSet) : Order?
    #   return nil if rows.empty?
    #   first = rows.first
    #
    #   Order.new(
    #     id: first["id"].as(Int64),
    #     total_cents: first["total_cents"].as(Int64),
    #     customer: Customer.new(
    #       id: first["customer_id"].as(Int64),
    #       name: first["customer_name"].as(String),
    #       email: first["customer_email"].as(String)
    #     ),
    #     items: rows.compact_map { |r|
    #       r["item_id"]? ? OrderItem.new(
    #         id: r["item_id"].as(Int64),
    #         product_id: r["product_id"].as(Int64),
    #         quantity: r["quantity"].as(Int32)
    #       ) : nil
    #     }
    #   )
    # end
    #
    # # Multiple aggregates: group by primary key
    # def find_orders_by_customer(customer_id : Int64) : Array(Order)
    #   rows = orders
    #     .where(orders: {customer_id: customer_id})
    #     .join(:customer)
    #     .left_join(:order_items)
    #     .order(orders: {id: :asc})
    #     .to_a
    #
    #   rows.group_by { |r| r["id"].as(Int64) }
    #       .values
    #       .compact_map { |group| build_order_from_rows(group) }
    # end
    # ```
    #
    # -------------------------------------------------------------------------
    # Pattern 4: Separate Queries
    # -------------------------------------------------------------------------
    #
    # Avoids JOINs, simpler queries, better for caching.
    #
    # ```crystal
    # def find_order_with_items(order_id : Int64) : Order?
    #   # Query 1: Order + Customer
    #   order_row = orders
    #     .where(orders: {id: order_id})
    #     .join(:customer)
    #     .first
    #
    #   return nil unless order_row
    #
    #   # Query 2: Items (separate query)
    #   item_rows = order_items
    #     .where(order_items: {order_id: order_id})
    #     .to_a
    #
    #   Order.new(
    #     id: order_row["id"].as(Int64),
    #     total_cents: order_row["total_cents"].as(Int64),
    #     customer: customer_from_row(order_row),
    #     items: item_rows.map { |r| order_item_from_row(r) }
    #   )
    # end
    # ```
    #
    # -------------------------------------------------------------------------
    # Pattern 5: Structure of Arrays (SoA)
    # -------------------------------------------------------------------------
    #
    # For performance-critical code. Better cache locality.
    #
    # ```crystal
    # # Instead of Array(OrderItem), use separate arrays
    # record OrderSoA,
    #   id : Int64,
    #   total_cents : Int64,
    #   customer : Customer,
    #   item_ids : Array(Int64),
    #   item_product_ids : Array(Int64),
    #   item_quantities : Array(Int32)
    #
    # def find_order_soa(order_id : Int64) : OrderSoA?
    #   row = execute_one(<<-SQL, [order_id])
    #     SELECT
    #       o.id, o.total_cents,
    #       c.id as customer_id, c.name, c.email,
    #       array_agg(i.id) as item_ids,
    #       array_agg(i.product_id) as item_product_ids,
    #       array_agg(i.quantity) as item_quantities
    #     FROM orders o
    #     JOIN customers c ON o.customer_id = c.id
    #     LEFT JOIN order_items i ON i.order_id = o.id
    #     WHERE o.id = $1
    #     GROUP BY o.id, c.id
    #   SQL
    #
    #   return nil unless row
    #
    #   OrderSoA.new(
    #     id: row["id"].as(Int64),
    #     total_cents: row["total_cents"].as(Int64),
    #     customer: customer_from_row(row),
    #     item_ids: row["item_ids"].as(Array(Int64?)).compact,
    #     item_product_ids: row["item_product_ids"].as(Array(Int64?)).compact,
    #     item_quantities: row["item_quantities"].as(Array(Int32?)).compact
    #   )
    # end
    # ```
  end
end
