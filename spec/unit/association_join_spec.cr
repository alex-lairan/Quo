require "../spec_helper"

# Relations for testing association joins

class InsurancePoliciesRelation < Quo::Relation
  schema :insurance_policies do
    primary_key :id, String
    column :policy_number, String
    column :user_id, String
    column :payment_provider_uuid, String
    column :status, String

    # Standard belongs_to - insurance_policies.user_id = users.id
    belongs_to :user, :user_id, :users

    # Custom key belongs_to - insurance_policies.payment_provider_uuid = stripe_subscriptions.stripe_id
    belongs_to :subscription, :payment_provider_uuid, :stripe_subscriptions, :stripe_id

    # has_many - claims.policy_id = insurance_policies.id
    has_many :claims, :policy_id, :claims
  end
end

class StripeSubscriptionsRelation < Quo::Relation
  schema :stripe_subscriptions do
    primary_key :id, String
    column :stripe_id, String
    column :customer_id, String
    column :status, String
  end
end

class ClaimsRelation < Quo::Relation
  schema :claims do
    primary_key :id, String
    column :policy_id, String
    column :amount_cents, Int64
    column :status, String

    belongs_to :policy, :policy_id, :insurance_policies
  end
end

class OrdersRelation < Quo::Relation
  schema :orders do
    primary_key :id, String
    column :customer_id, String
    column :total_cents, Int64

    belongs_to :customer, :customer_id, :customers
    has_many :order_items, :order_id, :order_items
    has_one :invoice, :order_id, :invoices
  end
end

describe "Association Joins" do
  describe "belongs_to with default key" do
    it "joins using association name" do
      relation = InsurancePoliciesRelation.new(test_adapter)
        .join(:user)

      sql, _ = relation.to_sql
      sql.should contain(%(INNER JOIN "users"))
      sql.should contain(%("insurance_policies"."user_id" = "users"."id"))
    end

    it "works with left_join" do
      relation = InsurancePoliciesRelation.new(test_adapter)
        .left_join(:user)

      sql, _ = relation.to_sql
      sql.should contain(%(LEFT JOIN "users"))
      sql.should contain(%("insurance_policies"."user_id" = "users"."id"))
    end
  end

  describe "belongs_to with custom key" do
    it "joins using custom target key" do
      relation = InsurancePoliciesRelation.new(test_adapter)
        .join(:subscription)

      sql, _ = relation.to_sql
      sql.should contain(%(INNER JOIN "stripe_subscriptions"))
      sql.should contain(%("insurance_policies"."payment_provider_uuid" = "stripe_subscriptions"."stripe_id"))
    end

    it "works with left_join" do
      relation = InsurancePoliciesRelation.new(test_adapter)
        .left_join(:subscription)

      sql, _ = relation.to_sql
      sql.should contain(%(LEFT JOIN "stripe_subscriptions"))
      sql.should contain(%("insurance_policies"."payment_provider_uuid" = "stripe_subscriptions"."stripe_id"))
    end
  end

  describe "has_many" do
    it "joins using association name" do
      relation = InsurancePoliciesRelation.new(test_adapter)
        .join(:claims)

      sql, _ = relation.to_sql
      sql.should contain(%(INNER JOIN "claims"))
      sql.should contain(%("insurance_policies"."id" = "claims"."policy_id"))
    end

    it "works with left_join" do
      relation = InsurancePoliciesRelation.new(test_adapter)
        .left_join(:claims)

      sql, _ = relation.to_sql
      sql.should contain(%(LEFT JOIN "claims"))
    end
  end

  describe "has_one" do
    it "joins using association name" do
      relation = OrdersRelation.new(test_adapter)
        .join(:invoice)

      sql, _ = relation.to_sql
      sql.should contain(%(INNER JOIN "invoices"))
      sql.should contain(%("orders"."id" = "invoices"."order_id"))
    end
  end

  describe "multiple association joins" do
    it "chains multiple association joins" do
      relation = InsurancePoliciesRelation.new(test_adapter)
        .join(:user)
        .join(:subscription)
        .left_join(:claims)

      sql, _ = relation.to_sql
      sql.should contain(%(INNER JOIN "users"))
      sql.should contain(%(INNER JOIN "stripe_subscriptions"))
      sql.should contain(%(LEFT JOIN "claims"))
    end
  end

  describe "mixed association and explicit joins" do
    it "combines association joins with explicit joins" do
      relation = InsurancePoliciesRelation.new(test_adapter)
        .join(:user)
        .join(:some_other_table, on: {insurance_policies: :other_id, eq: {some_other_table: :id}})

      sql, _ = relation.to_sql
      sql.should contain(%(INNER JOIN "users"))
      sql.should contain(%(INNER JOIN "some_other_table"))
    end
  end

  describe "association joins with where and select" do
    it "works with full query" do
      relation = InsurancePoliciesRelation.new(test_adapter)
        .select(
          insurance_policies: [:id, :policy_number, :status],
          users: [:name, :email],
          stripe_subscriptions: [:stripe_id, :status]
        )
        .join(:user)
        .join(:subscription)
        .where(insurance_policies: {status: "active"})
        .where { |e| e[:users][:email].is_not_null }
        .order(insurance_policies: {policy_number: :asc})
        .limit(50)

      sql, params = relation.to_sql
      sql.should contain(%("insurance_policies"."id"))
      sql.should contain(%("users"."name"))
      sql.should contain(%("stripe_subscriptions"."stripe_id"))
      sql.should contain(%(INNER JOIN "users" ON "insurance_policies"."user_id" = "users"."id"))
      sql.should contain(%(INNER JOIN "stripe_subscriptions" ON "insurance_policies"."payment_provider_uuid" = "stripe_subscriptions"."stripe_id"))
      sql.should contain(%(WHERE))
      sql.should contain(%(ORDER BY))
      sql.should contain(%(LIMIT))
      params.first.should eq("active")
    end
  end

  describe "error handling" do
    it "raises error for unknown association" do
      relation = InsurancePoliciesRelation.new(test_adapter)

      expect_raises(Quo::QueryError, /Unknown association 'nonexistent'/) do
        relation.join(:nonexistent)
      end
    end
  end
end
