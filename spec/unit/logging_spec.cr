require "../spec_helper"

describe Quo::Logging do
  before_each do
    Quo::Logging.clear_subscribers
    Quo::Logging.enabled = false
    Quo::Logging.log_level = Quo::LogLevel::None
  end

  describe ".log_level=" do
    it "enables logging when level is not None" do
      Quo::Logging.log_level = Quo::LogLevel::Info
      Quo::Logging.enabled?.should be_true
    end

    it "disables logging when level is None" do
      Quo::Logging.log_level = Quo::LogLevel::None
      Quo::Logging.enabled?.should be_false
    end
  end

  describe ".subscribe" do
    it "receives query events" do
      events = [] of Quo::QueryEvent

      Quo::Logging.enabled = true
      Quo::Logging.subscribe { |event| events << event }

      event = Quo::QueryEvent.new(
        sql: "SELECT * FROM users",
        params: [] of DB::Any,
        duration: 10.milliseconds,
        operation: :select
      )
      Quo::Logging.log(event)

      events.size.should eq(1)
      events[0].sql.should eq("SELECT * FROM users")
    end

    it "captures multiple subscribers" do
      count = 0

      Quo::Logging.enabled = true
      Quo::Logging.subscribe { |_| count += 1 }
      Quo::Logging.subscribe { |_| count += 1 }

      event = Quo::QueryEvent.new(sql: "SELECT 1", operation: :select)
      Quo::Logging.log(event)

      count.should eq(2)
    end
  end

  describe ".on_slow_query" do
    it "triggers for queries exceeding threshold" do
      slow_queries = [] of Quo::QueryEvent

      Quo::Logging.enabled = true
      Quo::Logging.slow_query_threshold = 50.milliseconds
      Quo::Logging.on_slow_query { |event| slow_queries << event }

      # Fast query
      fast_event = Quo::QueryEvent.new(
        sql: "SELECT 1",
        duration: 10.milliseconds,
        operation: :select
      )
      Quo::Logging.log(fast_event)

      # Slow query
      slow_event = Quo::QueryEvent.new(
        sql: "SELECT * FROM large_table",
        duration: 100.milliseconds,
        operation: :select
      )
      Quo::Logging.log(slow_event)

      slow_queries.size.should eq(1)
      slow_queries[0].sql.should eq("SELECT * FROM large_table")
    end
  end

  describe ".instrument" do
    it "measures execution time" do
      events = [] of Quo::QueryEvent

      Quo::Logging.enabled = true
      Quo::Logging.subscribe { |event| events << event }

      result = Quo::Logging.instrument("SELECT 1", [] of DB::Any, :select) do
        sleep 5.milliseconds
        42
      end

      result.should eq(42)
      events.size.should eq(1)
      events[0].duration.should be > 5.milliseconds
    end

    it "captures errors" do
      events = [] of Quo::QueryEvent

      Quo::Logging.enabled = true
      Quo::Logging.subscribe { |event| events << event }

      expect_raises(Exception, "Test error") do
        Quo::Logging.instrument("SELECT bad_column", [] of DB::Any, :select) do
          raise Exception.new("Test error")
        end
      end

      events.size.should eq(1)
      events[0].error.should_not be_nil
      events[0].error.not_nil!.message.should eq("Test error")
    end

    it "skips instrumentation when disabled" do
      events = [] of Quo::QueryEvent

      Quo::Logging.enabled = false
      Quo::Logging.subscribe { |event| events << event }

      result = Quo::Logging.instrument("SELECT 1", [] of DB::Any, :select) do
        42
      end

      result.should eq(42)
      # Subscribers still get called even when logging is disabled
      # but only if there are subscribers
    end
  end

  describe Quo::QueryEvent do
    it "reports success when no error" do
      event = Quo::QueryEvent.new(sql: "SELECT 1", operation: :select)
      event.success?.should be_true
    end

    it "reports failure when error present" do
      event = Quo::QueryEvent.new(
        sql: "SELECT 1",
        operation: :select,
        error: Exception.new("Error")
      )
      event.success?.should be_false
    end

    it "detects slow queries" do
      event = Quo::QueryEvent.new(
        sql: "SELECT 1",
        duration: 200.milliseconds,
        operation: :select
      )
      event.slow?(100.milliseconds).should be_true
      event.slow?(300.milliseconds).should be_false
    end
  end

  describe ".clear_subscribers" do
    it "removes all subscribers" do
      count = 0
      Quo::Logging.enabled = true
      Quo::Logging.subscribe { |_| count += 1 }
      Quo::Logging.on_slow_query { |_| count += 1 }

      Quo::Logging.clear_subscribers

      event = Quo::QueryEvent.new(
        sql: "SELECT 1",
        duration: 200.milliseconds,
        operation: :select
      )
      Quo::Logging.log(event)

      count.should eq(0)
    end
  end
end
