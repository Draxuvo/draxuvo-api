# Spec 064: el worker de trabajos no migra; solo la API lo hace al arrancar. Como los dos se despliegan a la vez, el worker
# espera a que no queden migraciones pendientes antes de tomar trabajos. Si pasa el tope, `call` devuelve false y quien la
# llama sale con error: Render reinicia el worker y vuelve a esperar.
class MigrationWait
  WAITING = "[migration_wait] esperando migraciones…".freeze
  READY = "[migration_wait] base al día".freeze
  DEFAULT_TIMEOUT = 600
  INTERVAL = 5

  attr_reader :timeout

  def self.for_database(logger:, env: ENV)
    new(
      pending: -> { ActiveRecord::Base.connection_pool.migration_context.needs_migration? },
      timeout: env.fetch("MIGRATION_WAIT_SECONDS", DEFAULT_TIMEOUT.to_s).to_i,
      logger: logger
    )
  end

  def initialize(pending:, timeout:, logger:, interval: INTERVAL,
                 clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, sleeper: ->(seconds) { sleep(seconds) })
    @pending = pending
    @timeout = timeout
    @interval = interval
    @clock = clock
    @sleeper = sleeper
    @logger = logger
  end

  def call
    started = @clock.call
    loop do
      unless @pending.call
        @logger.info(READY)
        return true
      end

      elapsed = @clock.call - started
      if elapsed >= @timeout
        @logger.error("[migration_wait] siguen pendientes tras #{@timeout} s")
        return false
      end

      @logger.info(WAITING)
      @sleeper.call([ @interval, @timeout - elapsed ].min)
    end
  end
end
