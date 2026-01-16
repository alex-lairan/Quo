require "log"

module Quo
  # Log levels for query logging
  enum LogLevel
    Debug
    Info
    Warn
    Error
    None
  end

  # Query event for instrumentation
  struct QueryEvent
    getter sql : String
    getter params : Array(DB::Any)
    getter duration : Time::Span
    getter operation : Symbol  # :select, :insert, :update, :delete
    getter rows_affected : Int64?
    getter error : Exception?

    def initialize(
      @sql : String,
      @params : Array(DB::Any) = [] of DB::Any,
      @duration : Time::Span = Time::Span.zero,
      @operation : Symbol = :select,
      @rows_affected : Int64? = nil,
      @error : Exception? = nil
    )
    end

    def success?
      @error.nil?
    end

    def slow?(threshold : Time::Span) : Bool
      @duration > threshold
    end
  end

  # Subscriber callback type
  alias QuerySubscriber = QueryEvent ->

  # Global logging and instrumentation configuration
  module Logging
    Log = ::Log.for("quo")

    @@log_level : LogLevel = LogLevel::None
    @@slow_query_threshold : Time::Span = 100.milliseconds
    @@subscribers : Array(QuerySubscriber) = [] of QuerySubscriber
    @@slow_query_handlers : Array(QuerySubscriber) = [] of QuerySubscriber
    @@enabled : Bool = false

    # Enable/disable logging
    def self.enabled=(value : Bool)
      @@enabled = value
    end

    def self.enabled?
      @@enabled
    end

    # Set log level
    def self.log_level=(level : LogLevel)
      @@log_level = level
      @@enabled = level != LogLevel::None
    end

    def self.log_level
      @@log_level
    end

    # Set slow query threshold
    def self.slow_query_threshold=(threshold : Time::Span)
      @@slow_query_threshold = threshold
    end

    def self.slow_query_threshold
      @@slow_query_threshold
    end

    # Subscribe to query events
    def self.subscribe(&block : QuerySubscriber)
      @@subscribers << block
    end

    # Subscribe to slow queries
    def self.on_slow_query(&block : QuerySubscriber)
      @@slow_query_handlers << block
    end

    # Clear all subscribers
    def self.clear_subscribers
      @@subscribers.clear
      @@slow_query_handlers.clear
    end

    # Log a query event
    def self.log(event : QueryEvent)
      return unless @@enabled

      # Format parameters for display
      params_str = event.params.empty? ? "" : " #{format_params(event.params)}"
      duration_str = "(#{format_duration(event.duration)})"

      message = "[QUO] #{event.sql}#{params_str} #{duration_str}"

      if err = event.error
        message += " ERROR: #{err.message}"
      end

      case @@log_level
      when LogLevel::Debug
        Log.debug { message }
      when LogLevel::Info
        Log.info { message }
      when LogLevel::Warn
        Log.warn { message }
      when LogLevel::Error
        Log.error { message } if event.error
      end

      # Notify subscribers
      @@subscribers.each do |subscriber|
        subscriber.call(event)
      end

      # Check for slow queries
      if event.slow?(@@slow_query_threshold)
        @@slow_query_handlers.each do |handler|
          handler.call(event)
        end
      end
    end

    # Wrap a block and log its execution
    def self.instrument(sql : String, params : Array(DB::Any), operation : Symbol, &block)
      return yield unless @@enabled || !@@subscribers.empty?

      start_time = Time.utc
      begin
        result = yield
        duration = Time.utc - start_time

        event = QueryEvent.new(
          sql: sql,
          params: params,
          duration: duration,
          operation: operation,
          rows_affected: result.is_a?(Int64) ? result : nil
        )
        log(event)

        result
      rescue ex
        duration = Time.utc - start_time
        event = QueryEvent.new(
          sql: sql,
          params: params,
          duration: duration,
          operation: operation,
          error: ex
        )
        log(event)
        raise ex
      end
    end

    private def self.format_params(params : Array(DB::Any)) : String
      formatted = params.map do |p|
        case p
        when String
          "\"#{p}\""
        when Nil
          "NULL"
        else
          p.to_s
        end
      end
      "[#{formatted.join(", ")}]"
    end

    private def self.format_duration(span : Time::Span) : String
      if span.total_milliseconds < 1
        "#{(span.total_milliseconds * 1000).round(2)}µs"
      elsif span.total_seconds < 1
        "#{span.total_milliseconds.round(2)}ms"
      else
        "#{span.total_seconds.round(2)}s"
      end
    end
  end
end
