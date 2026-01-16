require "../spec_helper"

describe Quo::Introspection::IntrospectedColumn do
  describe "#initialize" do
    it "stores column metadata" do
      column = Quo::Introspection::IntrospectedColumn.new(
        name: "id",
        data_type: "integer",
        nullable: false,
        default_value: nil,
        ordinal_position: 1,
        primary_key: true
      )

      column.name.should eq("id")
      column.data_type.should eq("integer")
      column.nullable?.should be_false
      column.default_value.should be_nil
      column.ordinal_position.should eq(1)
      column.primary_key?.should be_true
    end

    it "stores nullable columns" do
      column = Quo::Introspection::IntrospectedColumn.new(
        name: "description",
        data_type: "text",
        nullable: true,
        default_value: nil,
        ordinal_position: 5,
        primary_key: false
      )

      column.nullable?.should be_true
      column.primary_key?.should be_false
    end

    it "stores default values" do
      column = Quo::Introspection::IntrospectedColumn.new(
        name: "status",
        data_type: "varchar",
        nullable: false,
        default_value: "'active'",
        ordinal_position: 3,
        primary_key: false
      )

      column.default_value.should eq("'active'")
    end
  end
end

describe Quo::Introspection::IntrospectedIndex do
  describe "#initialize" do
    it "stores index metadata" do
      index = Quo::Introspection::IntrospectedIndex.new(
        name: "idx_users_email",
        table_name: "users",
        columns: ["email"],
        unique: true,
        primary: false,
        index_type: "btree"
      )

      index.name.should eq("idx_users_email")
      index.table_name.should eq("users")
      index.columns.should eq(["email"])
      index.unique?.should be_true
      index.primary?.should be_false
      index.index_type.should eq("btree")
    end

    it "stores composite indexes" do
      index = Quo::Introspection::IntrospectedIndex.new(
        name: "idx_orders_user_date",
        table_name: "orders",
        columns: ["user_id", "created_at"],
        unique: false,
        primary: false,
        index_type: "btree"
      )

      index.columns.size.should eq(2)
      index.columns.should contain("user_id")
      index.columns.should contain("created_at")
    end

    it "identifies primary key indexes" do
      index = Quo::Introspection::IntrospectedIndex.new(
        name: "users_pkey",
        table_name: "users",
        columns: ["id"],
        unique: true,
        primary: true,
        index_type: nil
      )

      index.primary?.should be_true
      index.unique?.should be_true
    end
  end
end

describe Quo::Introspection::ForeignKey do
  describe "#initialize" do
    it "stores foreign key metadata" do
      fk = Quo::Introspection::ForeignKey.new(
        name: "fk_orders_user",
        table_name: "orders",
        column_name: "user_id",
        referenced_table: "users",
        referenced_column: "id",
        on_delete: "CASCADE",
        on_update: nil
      )

      fk.name.should eq("fk_orders_user")
      fk.table_name.should eq("orders")
      fk.column_name.should eq("user_id")
      fk.referenced_table.should eq("users")
      fk.referenced_column.should eq("id")
      fk.on_delete.should eq("CASCADE")
      fk.on_update.should be_nil
    end

    it "stores on_update action" do
      fk = Quo::Introspection::ForeignKey.new(
        name: "fk_items_product",
        table_name: "order_items",
        column_name: "product_id",
        referenced_table: "products",
        referenced_column: "id",
        on_delete: "SET NULL",
        on_update: "CASCADE"
      )

      fk.on_delete.should eq("SET NULL")
      fk.on_update.should eq("CASCADE")
    end
  end
end

describe Quo::Introspection::IntrospectedTable do
  describe "#initialize" do
    it "aggregates table metadata" do
      columns = [
        Quo::Introspection::IntrospectedColumn.new(
          name: "id",
          data_type: "integer",
          nullable: false,
          default_value: nil,
          ordinal_position: 1,
          primary_key: true
        ),
        Quo::Introspection::IntrospectedColumn.new(
          name: "name",
          data_type: "varchar",
          nullable: false,
          default_value: nil,
          ordinal_position: 2,
          primary_key: false
        ),
      ]

      indexes = [
        Quo::Introspection::IntrospectedIndex.new(
          name: "users_pkey",
          table_name: "users",
          columns: ["id"],
          unique: true,
          primary: true,
          index_type: nil
        ),
      ]

      foreign_keys = [] of Quo::Introspection::ForeignKey

      table = Quo::Introspection::IntrospectedTable.new(
        name: "users",
        columns: columns,
        indexes: indexes,
        foreign_keys: foreign_keys,
        primary_key_columns: ["id"]
      )

      table.name.should eq("users")
      table.columns.size.should eq(2)
      table.indexes.size.should eq(1)
      table.foreign_keys.should be_empty
      table.primary_key_columns.should eq(["id"])
    end
  end

  describe "#column" do
    it "finds column by name" do
      columns = [
        Quo::Introspection::IntrospectedColumn.new(
          name: "id",
          data_type: "integer",
          nullable: false,
          default_value: nil,
          ordinal_position: 1,
          primary_key: true
        ),
        Quo::Introspection::IntrospectedColumn.new(
          name: "email",
          data_type: "varchar",
          nullable: false,
          default_value: nil,
          ordinal_position: 2,
          primary_key: false
        ),
      ]

      table = Quo::Introspection::IntrospectedTable.new(
        name: "users",
        columns: columns,
        indexes: [] of Quo::Introspection::IntrospectedIndex,
        foreign_keys: [] of Quo::Introspection::ForeignKey,
        primary_key_columns: ["id"]
      )

      column = table.column("email")
      column.should_not be_nil
      column.try(&.name).should eq("email")

      table.column("nonexistent").should be_nil
    end
  end
end
