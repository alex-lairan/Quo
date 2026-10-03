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
    getter params : Array(Quo::Value)
    getter duration : Time::Span          # Total time
    getter compile_time : Time::Span      # Time to build/compile SQL
    getter execute_time : Time::Span      # Time to execute at DB
    getter operation : Symbol             # :select, :insert, :update, :delete
    getter rows_affected : Int64?
    getter error : Exception?

    def initialize(
      @sql : String,
      params : Array(Quo::Value)? = nil,
      @duration : Time::Span = Time::Span.zero,
      @compile_time : Time::Span = Time::Span.zero,
      @execute_time : Time::Span = Time::Span.zero,
      @operation : Symbol = :select,
      @rows_affected : Int64? = nil,
      @error : Exception? = nil
    )
      @params = (params.nil? ? ([] of Quo::Value) : params).as(Array(Quo::Value))
    end

    def success?
      @error.nil?
    end

    def slow?(threshold : Time::Span) : Bool
      @duration > threshold
    end

    def slow_compile?(threshold : Time::Span) : Bool
      @compile_time > threshold
    end

    def slow_execute?(threshold : Time::Span) : Bool
      @execute_time > threshold
    end
  end

  # Subscriber callback type
  alias QuerySubscriber = QueryEvent ->

  # Custom logger interface
  # Implement this to use your own logger
  abstract class Logger
    abstract def debug(message : String)
    abstract def info(message : String)
    abstract def warn(message : String)
    abstract def error(message : String)
  end

  # Default STDERR adapter - simple and reliable
  class StderrLogAdapter < Logger
    def debug(message : String)
      STDERR.puts "\e[36m#{Time.utc} DEBUG - #{message}\e[0m"
    end

    def info(message : String)
      STDERR.puts "\e[32m#{Time.utc}  INFO - #{message}\e[0m"
    end

    def warn(message : String)
      STDERR.puts "\e[33m#{Time.utc}  WARN - #{message}\e[0m"
    end

    def error(message : String)
      STDERR.puts "\e[31m#{Time.utc} ERROR - #{message}\e[0m"
    end
  end

  # Global logging and instrumentation configuration
  module Logging
    @@log_level : LogLevel = LogLevel::None
    @@slow_query_threshold : Time::Span = 100.milliseconds
    @@slow_compile_threshold : Time::Span = 50.milliseconds
    @@subscribers : Array(QuerySubscriber) = [] of QuerySubscriber
    @@slow_query_handlers : Array(QuerySubscriber) = [] of QuerySubscriber
    @@enabled : Bool = false
    @@logger : Quo::Logger = StderrLogAdapter.new

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

    # Set slow compile threshold
    def self.slow_compile_threshold=(threshold : Time::Span)
      @@slow_compile_threshold = threshold
    end

    def self.slow_compile_threshold
      @@slow_compile_threshold
    end

    # Set custom logger
    def self.logger=(logger : Quo::Logger)
      @@logger = logger
    end

    def self.logger
      @@logger
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

      # Format timing information
      timing_str = if event.compile_time > Time::Span.zero || event.execute_time > Time::Span.zero
        compile = format_duration(event.compile_time)
        execute = format_duration(event.execute_time)
        total = format_duration(event.duration)
        "(compile: #{compile}, execute: #{execute}, total: #{total})"
      else
        "(#{format_duration(event.duration)})"
      end

      message = "[QUO] #{event.sql}#{params_str} #{timing_str}"

      if err = event.error
        message += " ERROR: #{err.message}"
      end

      # Log slow compile warning
      if event.slow_compile?(@@slow_compile_threshold)
        message += " [SLOW COMPILE]"
      end

      case @@log_level
      when LogLevel::Debug
        @@logger.debug(message)
      when LogLevel::Info
        @@logger.info(message)
      when LogLevel::Warn
        @@logger.warn(message)
      when LogLevel::Error
        @@logger.error(message) if event.error
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

    # Wrap a block and log its execution (legacy - no timing breakdown)
    def self.instrument(sql : String, params : Array(Quo::Value), operation : Symbol, &block)
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

    # Instrument with separate compile and execute timing
    def self.instrument_with_timing(
      sql : String,
      params : Array(Quo::Value),
      operation : Symbol,
      compile_time : Time::Span,
      &block
    )
      return yield unless @@enabled || !@@subscribers.empty?

      execute_start = Time.utc
      begin
        result = yield
        execute_time = Time.utc - execute_start
        total_duration = compile_time + execute_time

        event = QueryEvent.new(
          sql: sql,
          params: params,
          duration: total_duration,
          compile_time: compile_time,
          execute_time: execute_time,
          operation: operation,
          rows_affected: result.is_a?(Int64) ? result : nil
        )
        log(event)

        result
      rescue ex
        execute_time = Time.utc - execute_start
        total_duration = compile_time + execute_time

        event = QueryEvent.new(
          sql: sql,
          params: params,
          duration: total_duration,
          compile_time: compile_time,
          execute_time: execute_time,
          operation: operation,
          error: ex
        )
        log(event)
        raise ex
      end
    end

    private def self.format_params(params : Array(Quo::Value)) : String
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
