require "../spec_helper"

describe Quo::ExpressionBuilder do
  describe "column access" do
    it "creates ColumnRef via table[:column]" do
      builder = Quo::ExpressionBuilder.new
      col = builder[:contracts][:status]

      col.should be_a(Quo::ColumnRef)
      col.table.should eq(:contracts)
      col.column.should eq(:status)
    end
  end

  describe "comparison operators" do
    it "creates Eq expression" do
      builder = Quo::ExpressionBuilder.new
      expr = builder[:contracts][:status] == "active"

      expr.should be_a(Quo::Eq)
      expr.column.table.should eq(:contracts)
      expr.column.column.should eq(:status)
      expr.value.should eq("active")
    end

    it "creates NotEq expression" do
      builder = Quo::ExpressionBuilder.new
      expr = builder[:contracts][:status] != "deleted"

      expr.should be_a(Quo::NotEq)
    end

    it "creates Gt expression" do
      builder = Quo::ExpressionBuilder.new
      expr = builder[:contracts][:amount] > 1000

      expr.should be_a(Quo::Gt)
    end

    it "creates Gte expression" do
      builder = Quo::ExpressionBuilder.new
      expr = builder[:contracts][:amount] >= 1000

      expr.should be_a(Quo::Gte)
    end

    it "creates Lt expression" do
      builder = Quo::ExpressionBuilder.new
      expr = builder[:contracts][:amount] < 1000

      expr.should be_a(Quo::Lt)
    end

    it "creates Lte expression" do
      builder = Quo::ExpressionBuilder.new
      expr = builder[:contracts][:amount] <= 1000

      expr.should be_a(Quo::Lte)
    end
  end

  describe "logical operators" do
    it "creates And expression with &" do
      builder = Quo::ExpressionBuilder.new
      expr = (builder[:contracts][:status] == "active") & (builder[:contracts][:amount] >= 1000)

      expr.should be_a(Quo::And)
      expr.left.should be_a(Quo::Eq)
      expr.right.should be_a(Quo::Gte)
    end

    it "creates Or expression with |" do
      builder = Quo::ExpressionBuilder.new
      expr = (builder[:contracts][:status] == "active") | (builder[:contracts][:status] == "pending")

      expr.should be_a(Quo::Or)
      expr.left.should be_a(Quo::Eq)
      expr.right.should be_a(Quo::Eq)
    end

    it "chains logical operators" do
      builder = Quo::ExpressionBuilder.new
      # (status == "active" OR status == "pending") AND amount >= 1000
      expr = ((builder[:contracts][:status] == "active") | (builder[:contracts][:status] == "pending")) & (builder[:contracts][:amount] >= 1000)

      expr.should be_a(Quo::And)
      expr.left.should be_a(Quo::Or)
      expr.right.should be_a(Quo::Gte)
    end
  end

  describe "SQL operators" do
    it "creates Like expression" do
      builder = Quo::ExpressionBuilder.new
      expr = builder[:contracts][:name].like("%Acme%")

      expr.should be_a(Quo::Like)
      expr.pattern.should eq("%Acme%")
    end

    it "creates ILike expression" do
      builder = Quo::ExpressionBuilder.new
      expr = builder[:contracts][:name].ilike("%acme%")

      expr.should be_a(Quo::ILike)
      expr.pattern.should eq("%acme%")
    end

    it "creates In expression with array" do
      builder = Quo::ExpressionBuilder.new
      expr = builder[:contracts][:status].in(["active", "pending"])

      expr.should be_a(Quo::In)
      expr.values.should eq(["active", "pending"])
    end

    it "creates IsNull expression" do
      builder = Quo::ExpressionBuilder.new
      expr = builder[:contracts][:deleted_at].is_null

      expr.should be_a(Quo::IsNull)
    end

    it "creates IsNotNull expression" do
      builder = Quo::ExpressionBuilder.new
      expr = builder[:contracts][:deleted_at].is_not_null

      expr.should be_a(Quo::IsNotNull)
    end

    it "creates Between expression" do
      builder = Quo::ExpressionBuilder.new
      expr = builder[:contracts][:amount].between(1000, 5000)

      expr.should be_a(Quo::Between)
      expr.min.should eq(1000)
      expr.max.should eq(5000)
    end
  end

  describe "raw expressions" do
    it "creates Raw expression" do
      builder = Quo::ExpressionBuilder.new
      expr = builder.raw("NOW()")

      expr.should be_a(Quo::Raw)
      expr.sql.should eq("NOW()")
      expr.params.should be_empty
    end

    it "creates Raw expression with params" do
      builder = Quo::ExpressionBuilder.new
      expr = builder.raw("$1::uuid", "some-uuid")

      expr.should be_a(Quo::Raw)
      expr.sql.should eq("$1::uuid")
      expr.params.should eq(["some-uuid"])
    end
  end

  describe "not expressions" do
    it "creates Not expression" do
      builder = Quo::ExpressionBuilder.new
      inner = builder[:contracts][:status] == "deleted"
      expr = builder.not(inner)

      expr.should be_a(Quo::Not)
      expr.expression.should be_a(Quo::Eq)
    end
  end
end

describe Quo::ColumnRef do
  it "stores table and column" do
    col = Quo::ColumnRef.new(:contracts, :status)

    col.table.should eq(:contracts)
    col.column.should eq(:status)
  end

  it "supports logical operators" do
    col = Quo::ColumnRef.new(:contracts, :status)
    eq = col == "active"
    other_eq = Quo::ColumnRef.new(:contracts, :amount) >= 1000

    and_expr = eq & other_eq
    and_expr.should be_a(Quo::And)

    or_expr = eq | other_eq
    or_expr.should be_a(Quo::Or)
  end
end
